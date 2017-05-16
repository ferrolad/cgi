package XFSQueue;
use strict;
use JSON;

our $DEBUG;

sub getOpts {
	my %opts = grep { ref($_) eq '' } @_;
	my @coderefs = grep { ref($_) eq 'CODE' } @_;
	return(\%opts, \@coderefs);
}

sub read_pids {
        my ($pidfile) = @_;
	open PID, $pidfile||die("Couldn't open file: $!");
	flock(PID, 1)||die("Couldn't flock: $!");
	my $contents .= join('',<PID>);
	close PID;

	my @result;
	push @result, $1 while $contents =~ s/(\d+)//;
	return @result;
}

sub filter_alive { return grep { kill 0, $_ } @_; }

sub limitSrvWorkers {
	my($max_process_count) = @_;
	my $pidfile = "$1.pid" if $0 =~ /(.*)\.\w+/;
	die if !$pidfile;

	open(PID, ">>$pidfile")||die("Couldn't open file: $!");
	flock(PID, 2)||die("Couldn't flock: $!");
	print PID "$$\n";
	close PID;

	my @live_pids = filter_alive(read_pids($pidfile));

	open(PID, ">$pidfile")||die("Couldn't open file: $!");
	flock(PID, 2)||die("Couldn't flock: $!");
	print PID "@live_pids\n";
	close PID;

	print("Max processes count exceeded\n"), exit if int(@live_pids) > ($max_process_count||1);
}

sub runPollingLoop {
	my $url = shift;
	my ($opts, $coderefs) = &getOpts(@_);
	my $callback = $coderefs->[0];
	my $ua = LWP::UserAgent->new(agent => "XFS-FSAgent", timeout => 180);

	my $cx;
	while($cx++<1000)
	{
		print ".\n";
		my $res = $ua->post($url, $opts)->content;
		print "$res\n";
		my $task = eval { JSON::decode_json( $res ) } if length($res);
		print STDERR "Error while requesting API: $@\n" if $@;
		sleep(5), next if !$task;

		my $finish_cb = sub { $ua->post($url, { %$opts, op => 'queue_transfer_done', %$task }) };
		my $error_cb = sub { $ua->post($url, { %$opts, op => 'transfer_error', %$task, error => $_[0] }) };
		my $progress_cb = sub { $ua->post($url, { %$opts, op => 'transfer_progress', %$task, @_ }) };

		&$callback($task, $finish_cb, $error_cb, $progress_cb);
	}
}

1;
