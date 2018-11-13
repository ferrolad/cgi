#!/usr/bin/perl
$|++;

use strict;
use lib 'Modules';
use XFileConfig;
use Session;
use List::Util qw(sum);
use JSON;
use Getopt::Long;
use POSIX qw(isatty);
use Data::Dumper;

my $ses = Session->new();
my $db= $ses->db;

exit if $ENV{REQUEST_METHOD}; # Disable web access
   
sub PrintHelpAndExit {
   print STDERR <<OUT
Usage:
   $0 --brief   # Generate brief report
   $0 --detailed   # Generate detailed report
OUT
;
   exit(-1);
}

sub DBToFileCheck {
   my (@servers) = @_;

   local *gen_iterator  = sub {
      my ($query, @bind) = @_;
      my ($pos, $increment) = (0, 100);
      return sub {
         my $result = $db->SelectARef("$query LIMIT $pos, $increment", @bind) if $pos % $increment == 0;
         $pos += $increment - $pos % $increment;
         return @$result;
      }
   };

        local *selectByFileReal = sub {
                my $file_reals = join("','", @_);
                return $db->SelectARef("SELECT * FROM Files WHERE file_real IN ('$file_reals')");
        };

   # Polling servers to ensure that all files are in place
   my %missing_on_server;
   for my $server (@servers) {
      my $it = gen_iterator("SELECT * FROM Files WHERE srv_id=? GROUP BY file_real", $server->{srv_id});
      while(my @files = $it->()) { 
         print ".";
         my $res = $ses->api2($server->{srv_id}, { op => 'check_files', files =>  JSON::encode_json(\@files) });
         my $missing = eval { JSON::decode_json($res) };
         die($@) if !ref($missing);
                        $missing = selectByFileReal(map { $_->{file_real} } @$missing); # Respect anti-dupe system
         push @{ $missing_on_server{$server->{srv_id}} }, @$missing;
      }
   }
   return %missing_on_server;
}

sub FileToDBCheck {
   my (@servers) = @_;
   # Polling servers for the files list
   my %missing_in_db;
   for my $server (@servers) {
      my $res = $ses->api2($server->{srv_id}, { op => 'get_files_list' });
      my $dirs = eval { JSON::decode_json($res) };
      for my $dx(@$dirs) {
         my $res = $ses->api2($server->{srv_id}, { op => 'get_files_list', dx => $dx });
         my $files = eval { JSON::decode_json($res) };
         my @missing = grep { !$db->SelectOne("SELECT file_id FROM Files WHERE file_real=?", $_) } @$files;
         push @{ $missing_in_db{$server->{srv_id}} }, map {
            { srv_id => $server->{srv_id},
              dx => $dx,
              file_real => $_
            } } @missing;
      }
   }
   return %missing_in_db;
}

sub BriefReport {
   my ($missing_on_server, $missing_in_db) = @_;
   for(keys (%$missing_on_server)) {
      print scalar(@{$missing_on_server->{$_}})||0, " files are not accessible on server #$_\n";
   }
   for(keys (%$missing_in_db)) {
      print scalar(@{$missing_in_db->{$_}})||0, " files are not linked to db on server #$_\n";
   }
}

sub DetailedReport {
   my ($missing_on_server, $missing_in_db) = @_;

   print "The following files are missing on the fileserver:\n";
   for(sort(keys %$missing_on_server)) {
      print "$c->{site_url}/$_->{file_code}   $_->{file_name}\n" for @{ $missing_on_server->{$_} };
   }

   print "The following files are not linked in DB:\n";
   for(sort(keys %$missing_in_db)) {
      print "$_->{dx}/$_->{file_real}\n" for @{ $missing_in_db->{$_} };
   }
}

sub withNestedLists {
   # Apply $callback for each list nested in $hashref
   my ($hashref, $callback) = @_;
   for(keys %$hashref) {
      my @list = @{ $hashref->{$_} };
      &$callback(@list);
   }
}

# Parsing CLI opts
&PrintHelpAndExit() if !@ARGV;
my %opts;
my $result = GetOptions(\%opts, "brief", "detailed");
&PrintHelpAndExit() if !$result;

# Running checks
my $servers = $db->SelectARef("SELECT * FROM Servers");
my %missing_on_server = &DBToFileCheck(@$servers);
my %missing_in_db = &FileToDBCheck(@$servers);

# Generating reports
&BriefReport(\%missing_on_server, \%missing_in_db) if $opts{brief};
&DetailedReport(\%missing_on_server, \%missing_in_db) if $opts{detailed};

my $to_delete;
withNestedLists(\%missing_on_server, sub { $to_delete += int scalar(@_) });
withNestedLists(\%missing_in_db, sub { $to_delete += int scalar(@_) });

if(!$to_delete) {
   print "All ok\n";
   exit(0);
}

if(isatty(fileno(\*STDOUT))) {
   # Output is a terminal - so also offer to delete
   print "You're about to delete $to_delete files, type 'yes' to continue: ";
   my $line = <STDIN>;
   chomp($line);
   if($line eq 'yes') {
      withNestedLists(\%missing_on_server, sub { $ses->DeleteFilesMass(\@_) });
      withNestedLists(\%missing_in_db, sub {
         $_->{file_real_id} = $_->{dx} * $c->{files_per_folder} for @_;
         my $list = join ':', map{ "$_->{file_real_id}-$_->{file_real}" } @_;
         $ses->api2($_[0]->{srv_id}, {
            op => 'del_files',
            list => $list,
         });
      });
   }
}
