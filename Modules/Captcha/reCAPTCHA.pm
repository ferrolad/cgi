package Captcha::reCAPTCHA;

use warnings;
use strict;
use Carp;
use LWP::UserAgent;
use HTML::Tiny;

our $VERSION = '0.93';

use constant API_SERVER => 'http://www.google.com/recaptcha/api';
use constant API_SECURE_SERVER =>
 'https://www.google.com/recaptcha/api';
use constant API_VERIFY_SERVER => 'http://www.google.com';
use constant SERVER_ERROR      => 'recaptcha-not-reachable';

sub new {
  my $class = shift;
  my $self = bless {}, $class;
  $self->_initialize( @_ );
  return $self;
}

sub _initialize {
  my $self = shift;
  my $args = shift || {};

  croak "new must be called with a reference to a hash of parameters"
   unless 'HASH' eq ref $args;
}

sub _html { shift->{_html} ||= HTML::Tiny->new }

sub get_options_setter {
  my $self = shift;
  my $options = shift || return '';

  croak "The argument to get_options_setter must be a hashref"
   unless 'HASH' eq ref $options;

  my $h = $self->_html;

  return $h->script(
    { type => 'text/javascript' },
    "\n//<![CDATA[\n"
     . "var RecaptchaOptions = "
     . $h->json_encode( $options )
     . ";\n//]]>\n"
  ) . "\n";
}

sub get_html
{
   my ($self,$pubkey) = @_;
my $html = <<EOP
<script type="text/javascript">
var RecaptchaOptions = {theme: 'custom',custom_theme_widget: 'recaptcha_widget'};
</script>
<div id="recaptcha_widget" style="display:none"><div id="recaptcha_image" class="pic"></div>
<div class="recaptcha_only_if_incorrect_sol" style="color:red">Incorrect, please try again</div>
Type the two words:<br><input type="text" id="recaptcha_response_field" name="recaptcha_response_field">
<div><a href="javascript:Recaptcha.reload()">another captcha</a></div>
<script type="text/javascript" src="http://www.google.com/recaptcha/api/challenge?k=$pubkey"></script>
EOP
;
}

sub get_html1 {
  my $self = shift;
  my ( $pubkey, $error, $use_ssl, $options ) = @_;

  croak
   "To use reCAPTCHA you must get an API key from https://www.google.com/recaptcha/admin/create"
   unless $pubkey;

  my $h = $self->_html;
  my $server = $use_ssl ? API_SECURE_SERVER : API_SERVER;

  my $query = { k => $pubkey };
  if ( $error ) {
    # Handle the case where the result hash from check_answer
    # is passed.
    if ( 'HASH' eq ref $error ) {
      return '' if $error->{is_valid};
      $error = $error->{error};
    }
    $query->{error} = $error;
  }
  my $qs = $h->query_encode( $query );

  return join(
    '',
    $self->get_options_setter( $options ),
    $h->script(
      {
        type => 'text/javascript',
        src  => "$server/challenge?$qs",
      }
    ),
    "\n",
    $h->noscript(
      [
        $h->iframe(
          {
            src         => "$server/noscript?$qs",
            height      => 300,
            width       => 500,
            frameborder => 0
          }
        ),
        $h->textarea(
          {
            name => 'recaptcha_challenge_field',
            rows => 3,
            cols => 40
          }
        ),
        $h->input(
          {
            type  => 'hidden',
            name  => 'recaptcha_response_field',
            value => 'manual_challenge'
          }
        )
      ]
    ),
    "\n"
  );
}

sub _post_request {
  my $self = shift;
  my ( $url, $args ) = @_;

  my $ua = LWP::UserAgent->new();
  return $ua->post( $url, $args );
}

sub check_answer {
  my $self = shift;
  my ( $privkey, $remoteip, $challenge, $response ) = @_;

  croak
   "To use reCAPTCHA you must get an API key from https://www.google.com/recaptcha/admin/create"
   unless $privkey;

  croak "For security reasons, you must pass the remote ip to reCAPTCHA"
   unless $remoteip;

  return { is_valid => 0, error => 'incorrect-captcha-sol' }
   unless $challenge && $response;

  my $resp = $self->_post_request(
    API_VERIFY_SERVER . '/recaptcha/api/verify',
    {
      privatekey => $privkey,
      remoteip   => $remoteip,
      challenge  => $challenge,
      response   => $response
    }
  );

  if ( $resp->is_success ) {
    my ( $answer, $message ) = split( /\n/, $resp->content, 2 );
    if ( $answer =~ /true/ ) {
      return { is_valid => 1 };
    }
    else {
      chomp $message;
      return { is_valid => 0, error => $message };
    }
  }
  else {
    return { is_valid => 0, error => SERVER_ERROR };
  }
}

1;
