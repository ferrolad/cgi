#!/usr/bin/perl -X
use strict;

use lib '.';
use XFileConfig;
use Session;
use XUtils;

use CGI::Carp qw(fatalsToBrowser);

our $ses = Session->new;
our $db = $ses->db;
our $f = $ses->f;

if($ENV{REQUEST_METHOD})
{
   # Script is requested through the web interface, so checking for the admin priviliges
   my $user = XUtils::CheckAuth($ses, $ses->getCookie( $ses->{auth_cook} ));
   $ses->message("Access denied"), exit if !$user || !$user->{usr_adm};
}

$|++;
print"Content-type:text/html\n\n";

$db->Exec("INSERT INTO Misc SET name='last_cron_time', value=? ON DUPLICATE KEY UPDATE value=?",time,time);

if($ARGV[0])
{
   # Run a single cronjob
   my $filename = "$c->{cgi_path}/Engine/Cronjobs/$ARGV[0].pm";
   die("No such file: $filename") if ! -e $filename;
   eval { LoadCronjobHandler($ARGV[0])->() };
   print "$@" if $@;
}
else
{
   # Run all cronjobs
   opendir(DIR, "$c->{cgi_path}/Engine/Cronjobs/")||return;
   
   foreach my $fn (readdir(DIR))
   {
      next unless $fn =~ /^(\w+)\.pm$/i;
      eval { LoadCronjobHandler($1)->() };
      print "$@" if $@;
   }

   closedir(DIR);
}

print"-----------------------<br>ALL DONE<br><br><a href='$c->{site_url}/?op=admin_servers'>Back to server management</a>";

sub LoadCronjobHandler
{
   my ($name) = @_;
   my $filename = "$c->{cgi_path}/Engine/Cronjobs/$name.pm";
   my $module = "Engine::Cronjobs::$name";
   
   if(!eval { require $filename })
   {
      print $@;
      return;
   }

   return \&{ "$module\::main" };
}
