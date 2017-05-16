package Log;

use strict;
use vars qw($VERSION);
use FileHandle;
use File::Path;

$VERSION = "1.00";

eval { require XFileConfig };
eval { require XFSConfig };
my $cgi_dir = $XFileConfig::c->{cgi_path} || $XFSConfig::c->{cgi_dir};

sub new {
	my ($class,%args) = @_;
	my $self;
	unless($args{notie}) {
		$self = tie *STDERR, __PACKAGE__, %args;
	} else {
		$self = \%args;
		bless $self, __PACKAGE__;
		open STDERR, "> /dev/null" or die $!;
		$self->OPEN; 		
	}
	return $self;
}

sub write {
	my $self = shift;
	my $level = shift;
	my $message = shift;
	my $time = gmtime(time);
	my $fd = $self->{FD};
	$message =~ s/\s*$//;
	print $fd "[$time][$$] $message\n"; 
	if($self->{callback}) {
		&{ $self->{callback} }($message);
	}
}

sub PRINT {
	my $self = shift;
	my $stderr = join '', @_;
	$self->write(1,$stderr); 
}

sub TIEHANDLE{
	my ($class, %args) = @_;;
	my $self = {};
	if ($args{filename}) {
		my $fp = '/dev/null';
		mkpath "$cgi_dir/logs";
		$fp = "$cgi_dir/logs/$args{filename}";
        open FD, ">> $fp";
        FD->autoflush(1);
		my $fd = *FD;
		$self->{FD} = $fd;
	}
	if ($args{callback}) {
		$self->{callback} = $args{callback};
	}
	bless $self, $class;
}
sub OPEN {
	my $self = shift;
	my $fp = '/dev/null';
	$fp = "$cgi_dir/logs/$self->{filename}";
	open FD, ">> $fp";
    FD->autoflush(1);
	my $fd = *FD;
	$self->{FD} = $fd;

}

sub CLOSE {
	my $self = shift;
	close $self->{FD};
}
sub DESTROY {
	my $self = shift;
	close $self->{FD};
	untie *STDERR;
}

1;
