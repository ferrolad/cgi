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
        fs_key => $self->{fs_key},
        @args
    }, 'Content_Type' => 'form-data');

    if($res->code == 500)
    {
      print STDERR "Error while adding torrent: ", $res->decoded_content, "\n";
      return;
    }

    eval { JSON::decode_json($res->decoded_content) } || $res->decoded_content;
}

1;
