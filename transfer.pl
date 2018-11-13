#!/usr/bin/perl

use strict;
use threads;
use threads::shared;
use lib '.';

use XFSConfig;
use LWP::UserAgent;
use Fcntl qw( :flock :DEFAULT );
use XUpload;
use File::Basename;
use Data::Dumper;

use Log;
Log->new(filename => 'transfer.log');

exit unless $c->{fs_key};
exit unless sysopen( PID, 'transfer.pid', O_RDWR | O_CREAT ) && flock( PID, LOCK_EX | LOCK_NB );
my %progress :shared;

while(1)
{
   my $ua = LWP::UserAgent->new(agent => "XFS-FSAgent", timeout => 180);

   for my $thr(threads->list)
   {
      if($thr->is_joinable)
      {
         $ua->post("$c->{site_cgi}/fs.cgi", { op => $progress{$thr->tid}->{error} ? "transfer_error" : "queue_transfer_done", fs_key => $c->{fs_key}, %{$progress{$thr->tid}} })
            if ref($progress{$thr->tid}) eq 'HASH';
         delete $progress{$thr->tid};
         $thr->join();
      }
      else
      {
         $ua->post("$c->{site_cgi}/fs.cgi", { op => "transfer_progress", fs_key => $c->{fs_key}, %{$progress{$thr->tid}} })
            if ref($progress{$thr->tid}) eq 'HASH';
      }
   }

   sleep(1), next if int(threads->list()) > 10;

   my $res = $ua->post("$c->{site_cgi}/fs.cgi", { op => "queue_transfer_next", fs_key => $c->{fs_key}, threads_count => int(threads->list()) });
   my $task = eval { JSON::decode_json($res->decoded_content) } if length($res->decoded_content);
   print STDERR "Failed while decoding JSON: ", $res->decoded_content, "\n" if $@;

   print Dumper(\%progress) if threads->list > 0;
   sleep(threads->list > 0 ? 1 : 5), next if !$task;

   threads->create(\&worker_thread, $task);
}

sub worker_thread
{
   my ($task) = @_;
   my $tid = threads->self->tid;
   $progress{$tid} = shared_clone({ file_real => $task->{file_real}, 'state' => 'WORKING', 'transferred' => '0', 'speed' => '0' });

   local *error = sub { $progress{$tid}->{state} = 'ERROR'; $progress{$tid}->{error} = shift() };

   print STDERR "Worker thread started: $task->{file_real}\n";

   ### Download with LWP
   my ($old_time, $old_size, $transferred);

   local *content_cb = sub {
      my ($buffer,$res) = @_;
      $transferred += length($buffer);
      print FILE $buffer;

      if(time>$old_time)
      {
         print STDERR "+\n";
         my $speed_kb = sprintf("%.0f", ($transferred-$old_size)/1024/(time-$old_time) );
         $old_time = time;
         $old_size = $transferred;

         $progress{$tid}->{speed} = $speed_kb;
         $progress{$tid}->{transferred} = $transferred;
      }
   };

   local *http_get = sub {
      my ($url, $dest) = @_;
      my $ua = LWP::UserAgent->new(agent => "XFS-TransferAgent", timeout => 180);

      print STDERR "Downloading $url to $dest\n";
      my $workdir = dirname($dest);
      mkdir($workdir, 0755) || die("Can't create directory at $workdir: $!") if ! -d $workdir;

      open(FILE, ">$dest") || die("Can't open $dest: $!");
      my $res = $ua->get( $url , ':content_cb' => \&content_cb );
      close(FILE);
   };

   local *format_transfer_error = sub {
      # Slurping file contents
      my ($file_path) = @_;
      open FILE, "$file_path";
      my $line = <FILE>;
      close FILE;
   
      # Anti-XSS
      $line =~ s/</&lt;/g;
      $line =~ s/>/&gt;/g;
   
      return "DL error: " . ($line || 'empty content received');
   };

   my $file_path = "$c->{upload_dir}/$task->{dx}/$task->{file_real}";
   eval { &http_get($task->{direct_link}, $file_path) };
   return error($@) if $@;

   my $size = -s $file_path;
   my $md5hash = XUpload::MD5Hash($file_path);
   return error("File not found") if ! -e $file_path;
   return error(format_transfer_error($file_path)) if $size != $task->{file_size} && $size < 16;
   return error(format_transfer_error($file_path)) if $md5hash ne $task->{file_md5} && $size < 16;
   return error("Filesize mismatch: expected $task->{file_size} bytes but got $size") if $size != $task->{file_size};

   if($task->{orig_link})
   {
      my $orig_dir = "$1/orig" if $c->{upload_dir} =~ /^(.*)\/uploads/;
      return error("No orig dir") if !$orig_dir;
      mkdir($orig_dir, 0755) || return error("Couldn't create directory at $orig_dir: $!") if ! -d $orig_dir;
      http_get($task->{orig_link}, "$orig_dir/$task->{dx}/$task->{file_real}") if $task->{orig_link};
   }

   print STDERR "Transfer completed\n";

   my $idir = $c->{htdocs_dir};
   $idir=~s/^(.+)\/.+$/$1\/i/;
   mkdir("$idir/$task->{dx}",0777) || die("Couldn't mkdir at $idir/$task->{dx}: $!") unless -d "$idir/$task->{dx}";

   &http_get($task->{thumb_url}, "$idir/$task->{dx}/$task->{file_real}_t.jpg") if $task->{thumb_url};
   &http_get($task->{image_url}, "$idir/$task->{dx}/".basename($task->{image_url})) if $task->{image_url};
}
