package Plugins::Captcha::recaptcha;
use LWP::UserAgent;
use JSON;

sub generate
{
   my ($self) = @_;
   return if $ses->{captcha_mode} !~ /^(3|recaptcha)$/i;
   die("No reCAPTCHA API keys") if !$c->{recaptcha_pub_key} || !$c->{recaptcha_pri_key};
   return <<BLOCK
<script src='https://www.google.com/recaptcha/api.js'></script>
<div class="g-recaptcha" data-sitekey="$c->{recaptcha_pub_key}"></div>
BLOCK
;
}

sub check
{
   my ($self, $f) = @_;
   return if $ses->{captcha_mode} !~ /^(3|recaptcha)$/i;
   my $res = LWP::UserAgent->new->post('https://www.google.com/recaptcha/api/siteverify',
      {
         response => $f->{'g-recaptcha-response'},
         secret => $c->{recaptcha_pri_key},
         remoteip => $ses->getIP,
      });
   my $ret = JSON::decode_json($res->decoded_content);
   return 1 if $ret->{success} eq 'true';
}

1;
