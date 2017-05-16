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
use IPN;

Log->new(filename => 'ipn.log', callback => sub { $Log::accum .= "$_[0]\n" });

my $ses = Session->new();
my $f = $ses->f;
my $db= $ses->db;

my $ipn = IPN->new($ses);

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
$transaction = eval { $_->verify($f) } while !$transaction && ($_ = pop(@available_plgs));

if($@) {
   print STDERR "$@\n";
   print "Content-type: text/html\n\nSome error occured";
   exit;
}

$ipn->setTransactionOpts($transaction, plugin => $1) if $_ =~ /([^:]+)$/;

if(!$transaction) {
   print STDERR "No plugins found\n";
   print "Content-type: text/html\n\nNo plugins";
   exit;
}
die('Resubmitting detected') if $transaction->{verified} && $transaction->{txn_id} eq $f->{txn_id};

unless($transaction->{usr_id})
{
   # Creating a new user
   $transaction->{login} = join '', map int rand 10, 1..7;
   while($db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$transaction->{login})){ $transaction->{login} = join '', map int rand 10, 1..7; }
   $transaction->{password} = $ses->randchar(10);
   $f->{payer_email} = $transaction->{email} if $transaction->{email};
   $db->Exec("INSERT INTO Users (usr_login,usr_email,usr_password,usr_created,usr_aff_id) VALUES (?,?,ENCODE(?,?),NOW(),?)",$transaction->{login},$f->{payer_email}||'',$transaction->{password},$c->{pasword_salt},$transaction->{aff_id}||0);
   $transaction->{usr_id} = $db->getLastInsertId;
   $db->Exec("UPDATE Transactions SET usr_id=? WHERE id=?",$transaction->{usr_id},$transaction->{id});
}
else
{
  my $xx = $db->SelectRow("SELECT usr_login, DECODE(usr_password,?) as password FROM Users WHERE usr_id=?",$c->{pasword_salt},$transaction->{usr_id});
  $transaction->{login} = $xx->{usr_login};
  $transaction->{password} = $xx->{password};
}

if($transaction->{ref_url} eq 'RESELLER') { $ipn->acceptResellersMoney($transaction); exit; }
my $days = $ipn->upgradePremium($transaction);

my $user = $db->SelectRow("SELECT *, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec 
                           FROM Users 
                           WHERE usr_id=?", $transaction->{usr_id} );

# Send email to user
my $t = $ses->CreateTemplate("payment_notification.html");
$t->param('amount' => $transaction->{amount},
                'days'   => $days,
                'expire' => $user->{usr_premium_expire},
                'login'  => $transaction->{login},
                'password' => $transaction->{password},
         );
$c->{email_text}=1;
$ses->SendMail($user->{usr_email}, $c->{email_from}, "$c->{site_name} Payment Notification", $t->output) if $user->{usr_email};

# Send email to admin
my $t = $ses->CreateTemplate("payment_notification_admin.html");
$t->param('amount' => $transaction->{amount},
                'days'   => $days,
                'expire' => $user->{usr_premium_expire},
                'usr_id' => $user->{usr_id},
                'usr_login' => $user->{usr_login},
         );
$c->{email_text}=0;
$ses->SendMail($c->{contact_email}, $c->{email_from}, "Received payment from $user->{usr_login}", $t->output);

&FinishSession($transaction);

#----------------------

sub FinishSession {
    my ($transaction) = @_;
    print STDERR  "Finishing session from '$ENV{REMOTE_ADDR}' - - - - - - - - - - - - - " ;
    if($f->{cart_order_id} || $f->{verificationString}) #2CO or CashU
    {
       my $loginfo="<br><br>Login: $transaction->{login}<br>Password: $transaction->{password}" if $transaction->{password};
       print("Content-type:text/html\n\nPayment complete.<br>Added Premium Days:".$days.$loginfo."<br><br>Back to main site: <a href='$c->{site_url}'>$c->{site_url}</a>");
       exit;
    }
    print"Content-type: text/plain\n\n$f->{out}";
    print STDERR  "Done." ;
    exit;
}

END {
    if($db) {
        $db->Exec("INSERT INTO IPNLogs SET usr_id=?, info=?, created=NOW()",
            $transaction->{usr_id}||0,
            $Log::accum||'');
    }
}
