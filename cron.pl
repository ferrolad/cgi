#!/usr/bin/perl -X
use strict;
use lib ".";

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
   $ses->message("Access denied"), exit if !$ses->getUser() || !$ses->getUser()->{usr_adm};
}

$|++;
print"Content-type:text/html\n\n";

$db->Exec("INSERT INTO Misc SET name='last_cron_time', value=? ON DUPLICATE KEY UPDATE value=?",time,time);

my $job_name = ucfirst($f->{op}||$ARGV[0]);

if($job_name)
{
   # Run a single cronjob
   my $filename = "$c->{cgi_path}/Engine/Cronjobs/$job_name.pm";
   die("No such file: $filename") if ! -e $filename;
   my $should_run = sub { return 1 }; # Explicitly requested by user, so avoid period check
   eval { LoadCronjobHandler($job_name)->($should_run) };
   print "$@" if $@;
}
else
{
   # Run all cronjobs
   opendir(DIR, "$c->{cgi_path}/Engine/Cronjobs/")||return;
   
   foreach my $fn (readdir(DIR))
   {
      my ($task_name) = $fn =~ /^(\w+)\.pm$/i;
      next if !$task_name;

      my $should_run = sub {
         my ($period_in_minutes) = @_;
         my $ts_name = sprintf("last_%s_time", lc($task_name));
         my $last_time = $ses->db->SelectOne( "SELECT value FROM Misc WHERE name=?", $ts_name )||0;
         return 0 if time() - $last_time < $period_in_minutes * 60;

         $db->Exec("INSERT INTO Misc SET name=?, value=? ON DUPLICATE KEY UPDATE value=?",$ts_name,time(),time());
         return 1;
      };

      eval { LoadCronjobHandler($task_name)->($should_run) };
      print "$@" if $@;
   }

   closedir(DIR);
}

my $redirect_to = $1 if $f->{redirect} =~ /^(admin_servers|admin_settings)$/;
$redirect_to ||= 'admin_servers';

print"-----------------------<br>ALL DONE<br><br><a href='$c->{site_url}/?op=$redirect_to'>Back to server management</a>";

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
