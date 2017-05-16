package Crypt::CipherSaber;

use strict;

use Carp;
use Scalar::Util 'reftype';

use vars '$VERSION';

$VERSION = '1.00';

sub new
{
	my ($class, $key, $N) = @_;

	if ( !( defined $N ) or ( $N < 1 ) )
	{
		$N = 1;
	}
	bless [ $key, [ 0 .. 255 ], $N ], $class;
}

sub crypt
{
	my ($self, $iv, $message) = @_;
	$self->_setup_key($iv);

	my $state   = $self->[1];
	my $output  = _do_crypt( $state, $message );
	$self->[1] = [ 0 .. 255 ];
	return $output;
}

sub encrypt
{
	my $self = shift;
	my $iv   = $self->_gen_iv();
	return $iv . $self->crypt( $iv, @_ );
}

sub decrypt
{
	my $self = shift;
	my ( $iv, $message ) = unpack( "a10a*", +shift );
	return $self->crypt( $iv, $message );
}

sub fh_crypt
{
	my ( $self, $in, $out, $iv ) = @_;

	for my $glob ($in, $out)
	{
		my $reftype = reftype( $glob ) || '';
		unless ($reftype eq 'GLOB')
		{
			require Carp;
			Carp::carp( 'Non-filehandle passed to fh_crypt()' );
			return;
		}
	}

	local *OUT = $out;
	if ( defined($iv) )
	{
		$iv = $self->_gen_iv() if length($iv) == 1;
		$self->_setup_key($iv);
		print OUT $iv;
	}

	my $state = $self->[1];

	my ( $buf, @vars );

	while (<$in>)
	{
		unless ($iv)
		{
			( $iv, $_ ) = unpack( "a10a*", $_ );
			$self->_setup_key($iv);
		}
		my $line;
		( $line, $state, @vars ) = _do_crypt( $state, $_, @vars );
		print OUT $line;
	}
	$self->[1] = [ 0 .. 255 ];
	return 1;
}

sub _gen_iv
{
	my $iv;
	for ( 1 .. 10 )
	{
		$iv .= chr( int( rand(256) ) );
	}
	return $iv;
}

sub _setup_key
{
	my $self   = shift;
	my $key    = $self->[0] . shift;
	my @key    = map { ord } split( //, $key );
	my $state  = $self->[1];
	my $j      = 0;
	my $length = @key;

	# repeat N times, for CS-2
	for ( 1 .. $self->[2] )
	{
		for my $i ( 0 .. 255 )
		{
			$j += ( $state->[$i] + ( $key[ $i % $length ] ) );
			$j %= 256;
			( @$state[ $i, $j ] ) = ( @$state[ $j, $i ] );
		}
	}
}

sub _do_crypt
{
	my ( $state, $message, $i, $j, $n ) = @_;

	my $output = '';

	for ( 0 .. ( length($message) - 1 ) )
	{
		$i++;
		$i %= 256;
		$j += $state->[$i];
		$j %= 256;
		@$state[ $i, $j ] = @$state[ $j, $i ];
		$n = $state->[$i] + $state->[$j];
		$n %= 256;
		$output .= chr( $state->[$n] ^ ord( substr( $message, $_, 1 ) ) );
	}

	return wantarray ? ( $output, $state, $i, $j, $n ) : $output;
}

1;
