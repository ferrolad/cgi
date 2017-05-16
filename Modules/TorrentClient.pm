package TorrentClient;
use strict;
use LWP::UserAgent;
use JSON;

sub new
{
    my $class = shift;
    my %opts = @_;
    $opts{rpc_url} ||= "http://127.0.0.1:9092/";
    $opts{rpc_agent} = LWP::UserAgent->new;
    bless \%opts, $class;
}

sub DESTROY
{
}

sub AUTOLOAD
{
	use vars qw($AUTOLOAD);
	my ($self, @args) = @_;
	( my $op = $AUTOLOAD ) =~ s{.*::}{};

    my $res = $self->{rpc_agent}->post($self->{rpc_url},
    {
        op => $op,
        @args
    }, 'Content_Type' => 'form-data');

    die($res->decoded_content) if $res->code == 500;

    eval { JSON::decode_json($res->decoded_content) } || $res->decoded_content;
}

1;
