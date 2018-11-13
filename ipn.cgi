#!/usr/bin/perl
use strict;
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
use lib '.';
use vars qw($ses);
use XFileConfig;
use Session;
use CGI;
use Data::Dumper;
use lib 'Plugins';
use Log;

Log->new(filename => 'ipn.log', callback => sub { $Log::accum .= "$_[0]\n" });

my $ses = Session->new();
my $f = $ses->f;
my $db= $ses->db;

# Logging CGI request
my $post = Dumper($f);
$post=~s/\r//g;
$post=~s/\$VAR1 = \{(.+)\};/$1/s;
$post=~s/\n+$//g;
print STDERR "POST data: $post";

# 1. Only the plugins that are set up by user should be available for IPNs.
# 2. Here we are using While() loop because we need to know which plugin exactly was
#    triggered in orded to put this in statistics.
#    Please don't use this part of code as a reference unless you really need a such kind of info.
#    Just evaluating $ses->getPlugins(...) in the scalar context is looking much better.

my $transaction;
my @available_plgs = grep { $c->{ $_->options->{account_field} } } $ses->getPlugins('Payments');
while(!$transaction && ($_ = pop(@available_plgs)))
{
  $transaction = eval { $_->verify($f) };
  print STDERR $@ if $@;
}

if($@) {
   print STDERR "$@\n";
   print "Content-type: text/html\n\nSome error occured";
   exit;
}

if(!$transaction) {
   print STDERR "No plugins found\n";
   print "Content-type: text/html\n\nNo plugins";
   exit;
}

if($transaction->{verified} && $transaction->{txn_id} eq $f->{txn_id})
{
   print "Content-type: text/html\n\nResubmitting detected\n";
   exit;
}

unless($transaction->{usr_id})
{
   # Creating a new user
   my $usersRegistry = $ses->require("Engine::Components::UsersRegistry");
   $transaction->{login} = $usersRegistry->randomLogin();
   $transaction->{password} = $ses->randchar(10);
   $f->{payer_email} = $transaction->{email} if $transaction->{email};

   $transaction->{usr_id} = $usersRegistry->createUser({
      login => $transaction->{login},
      email => $f->{payer_email},
      password => $transaction->{password},
      aff_id => $transaction->{aff_id}||0,
   });

   $db->Exec("UPDATE Transactions SET usr_id=? WHERE id=?",$transaction->{usr_id},$transaction->{id});
}
else
{
  my $xx = $db->SelectRow("SELECT usr_login FROM Users WHERE usr_id=?", $transaction->{usr_id});
  $transaction->{login} = $xx->{usr_login};
  $transaction->{password} = '*' x 6;
}

my $user = $db->SelectRow("SELECT *, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec 
                           FROM Users 
                           WHERE usr_id=?", $transaction->{usr_id} );

my $p = $ses->require("Engine::Components::PaymentAcceptor");
$p->processTransaction($transaction);

print"Content-type: text/plain\n\n$f->{out}";
print STDERR  "Done." ;
exit;

END {
    if($db) {
        $db->Exec("INSERT INTO IPNLogs SET usr_id=?, info=?, created=NOW()",
            $transaction->{usr_id}||0,
            $Log::accum||'');
    }
}
