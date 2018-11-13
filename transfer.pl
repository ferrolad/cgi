#!/usr/bin/perl
#
use strict;
use threads;
use threads::shared;

use XFSConfig;
use LWP::UserAgent;
use Fcntl qw( :flock :DEFAULT );
use XUpload;
use File::Basename;

use Log;
Log->new(filename => 'transfer.log');

exit unless sysopen( PID, 'transfer.pid', O_RDWR | O_CREAT ) && flock( PID, LOCK_EX | LOCK_NB );

my $lock :shared;

master_thread();

sub master_thread
{
   my $ua = LWP::UserAgent->new(agent => "XFS-FSAgent", timeout => 180);

   while(1)
   {
      $_->join() for(threads->list(threads::joinable));

      sleep(1), next if int(threads->list()) > 10;

      lock($lock);
      my $res = $ua->post("$c->{site_cgi}/fs.cgi", {
         op              => "queue_transfer_next",
         fs_key          => $c->{fs_key},
         threads_count   => int(threads->list()),
      });

      my $task = eval { JSON::decode_json($res->decoded_content) } if length($res->decoded_content);
      print STDERR "Error while requesting API: $@\n" if $@;
      sleep(5), next if !$task;

      threads->create(\&worker_thread, $task);
   }
}

sub worker_thread
{
   my ($task) = @_;
   my $ua = LWP::UserAgent->new(agent => "XFS-FSAgent", timeout => 180);

   print STDERR "Worker thread started: $task->{file_real}\n";

   my $url = "$c->{site_cgi}/fs.cgi";
   local *finish_cb = sub { lock($lock); $ua->post($url, { fs_key => $c->{fs_key}, op => 'queue_transfer_done', %$task }) };
   local *error_cb = sub { lock($lock); print STDERR "$_[0]\n"; $ua->post($url, { fs_key => $c->{fs_key}, op => 'transfer_error', %$task, error => $_[0] }) };
   local *progress_cb = sub { lock($lock); $ua->post($url, { fs_key => $c->{fs_key}, op => 'transfer_progress', %$task, @_ }) };

   ### Download with LWP
   my ($old_time, $old_size, $transferred);

   local *lwp_download_cb = sub {
      my ($buffer,$res) = @_;
      $transferred += length($buffer);
      print FILE $buffer;

      if(time>$old_time+5)
      {
         print STDERR "+\n";
         my $speed_kb = sprintf("%.0f", ($transferred-$old_size)/1024/(time-$old_time) );
         $old_time = time;
         $old_size = $transferred;

         lock($lock);
         progress_cb(speed => $speed_kb, transferred => $transferred);
      }
   };

   local *lwp_download = sub {
      my ($url, $dest) = @_;
      print STDERR "Downloading $url to $dest\n";
      my $workdir = dirname($dest);
      mkdir($workdir, 0755) || die("Can't create directory at $workdir: $!") if ! -d $workdir;

      open(FILE, ">$dest") || die("Can't open $dest: $!");
      my $res = $ua->get( $url , ':content_cb' => \&lwp_download_cb );
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
   eval { &lwp_download($task->{direct_link}, $file_path) };
   return error_cb($@) if $@;

   my $size = -s $file_path;
   my $md5hash = XUpload::MD5Hash($file_path);
   return error_cb("File not found") if ! -e $file_path;
   return error_cb(format_transfer_error($file_path)) if $size != $task->{file_size} && $size < 16;
   return error_cb(format_transfer_error($file_path)) if $md5hash ne $task->{file_md5} && $size < 16;
   return error_cb("Filesize mismatch: expected $task->{file_size} bytes but got $size") if $size != $task->{file_size};

   if($task->{orig_link})
   {
      my $orig_dir = "$1/orig" if $c->{upload_dir} =~ /^(.*)\/uploads/;
      return error_cb("No orig dir") if !$orig_dir;
      mkdir($orig_dir, 0755) || return error_cb("Couldn't create directory at $orig_dir: $!") if ! -d $orig_dir;
      lwp_download($task->{orig_link}, "$orig_dir/$task->{dx}/$task->{file_real}") if $task->{orig_link};
   }

   finish_cb();
   print STDERR "Transfer completed\n";

   # Perhaps we'd also download IMG or Thumb URL

   my $idir = $c->{htdocs_dir};
   $idir=~s/^(.+)\/.+$/$1\/i/;
   mkdir("$idir/$task->{dx}",0777) || die("Couldn't mkdir at $idir/$task->{dx}: $!") unless -d "$idir/$task->{dx}";

   &lwp_download($task->{thumb_url}, "$idir/$task->{dx}/$task->{file_real}_t.jpg") if $task->{thumb_url};
   &lwp_download($task->{image_url}, "$idir/$task->{dx}/".basename($task->{image_url})) if $task->{image_url};
}
