#!/usr/bin/perl
use strict;
use XFSConfig;
use CGI::Simple;
$CGI::Simple::DISABLE_UPLOADS = 0;
$CGI::Simple::POST_MAX = -1;
use CGI::Carp qw(fatalsToBrowser);
use Log;

Log->new(filename => 'up.log');

print("Access-Control-Allow-Origin: *\n");
print("Content-type: text/plain\n\nOK"), exit if $ENV{REQUEST_METHOD} eq 'OPTIONS';

my $q = new CGI::Simple;
my $fname = $q->param('file');
my $sid = $q->param('sid');

$sid =~ s/\W//g;
$fname =~ s/\W//g;

die("No SID specified") if !$sid;
die("No filename") if !$fname;

unless(-d "$c->{temp_dir}/$sid")
{
   my $mode = 0777;
   mkdir("$c->{temp_dir}/$sid",$mode) || die("Couldn't create directory: $!");
   chmod $mode,"$c->{temp_dir}/$sid";
}
$q->upload($fname, "$c->{temp_dir}/$sid/$fname") || &msg("Can't move file $fname:$!");

&msg("OK");
      
sub msg
{
   my $txt=shift;
   print"Content-type:text/html\n\n<$txt>";
   exit;
}
