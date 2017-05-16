#!/usr/bin/perl
use strict;
use XFSConfig;
use XFSQueue;
use LWP::UserAgent;
use JSON;
use XUpload;
use File::Basename;

$|++;

my $ua = LWP::UserAgent->new(agent => "XFS-FSAgent", timeout => 360);

XFSQueue::limitSrvWorkers(2);
XFSQueue::runPollingLoop("$c->{site_cgi}/fs.cgi",
	op              => "queue_transfer_next",
	fs_key		=> $c->{fs_key},
	\&processTask,
);

sub processTask
{
	my ($task, $finish_cb, $err_cb, $progress_cb) = @_;
	my $file_path = "$c->{upload_dir}/$task->{dx}/$task->{file_real}";
	&lwp_download($task->{direct_link}, $file_path,
		progress => $progress_cb);

	my $size = -s $file_path;
	my $md5hash = XUpload::MD5Hash($file_path);
	return &$err_cb("File not found") if ! -e $file_path;
	return &$err_cb(&format_transfer_error($file_path)) if $size != $task->{file_size} && $size < 16;
	return &$err_cb(&format_transfer_error($file_path)) if $md5hash ne $task->{file_md5} && $size < 16;
	return &$err_cb("Filesize mismatch: expected $task->{file_size} bytes but got $size") if $size != $task->{file_size};

	my $idir = $c->{htdocs_dir};
	$idir=~s/^(.+)\/.+$/$1\/i/;
	mkdir("$idir/$task->{dx}",0777) unless -d "$idir/$task->{dx}";

	&lwp_download($task->{thumb_url}, "$idir/$task->{dx}/$task->{file_real}_t.jpg") if $task->{thumb_url};
	&lwp_download($task->{image_url}, "$idir/$task->{dx}/".basename($task->{image_url})) if $task->{image_url};

	&$finish_cb();
}

sub lwp_download
{
	my ($url, $dest, %opts) = @_;

	my $workdir = dirname($dest);
	mkdir($workdir, 0777)||die if ! -d $workdir;

	open(FILE, ">$dest")||die;
	my ($old_time, $old_size, $transferred);
	my $res = $ua->get( $url , ':content_cb' => sub {
		my ($buffer,$res) = @_;
		$transferred += length($buffer);
		print FILE $buffer;

		if(time>$old_time+5)
		{
			print "+\n";
			my $speed_kb = sprintf("%.0f", ($transferred-$old_size)/1024/(time-$old_time) );
			$old_time = time;
			$old_size = $transferred;

			my $progress_cb = $opts{progress};
			&$progress_cb(speed => $speed_kb, transferred => $transferred) if $progress_cb;
		}
	} );
	close FILE;
}

sub format_transfer_error
{
	# Slurping file contents
	my ($file_path) = @_;
	open FILE, "$file_path";
	my $line = <FILE>;
	close FILE;

	# Anti-XSS
	$line =~ s/</&lt;/g;
	$line =~ s/>/&gt;/g;

	return "DL error: $line";
}
