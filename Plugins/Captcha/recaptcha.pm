package Plugins::Captcha::recaptcha;
use Captcha::reCAPTCHA;

sub generate
{
   my ($self) = @_;
   return if $c->{captcha_mode} !~ /^(3|recaptcha)$/i;
   die("No reCAPTCHA API keys") if !$c->{recaptcha_pub_key} || !$c->{recaptcha_pri_key};
   my $style = "<style>\n#recaptcha_image { margin: auto; }\n#recaptcha_widget { text-align: center; }\n</style>";
   return $style . '<table><tr><td>' . Captcha::reCAPTCHA->new->get_html( $c->{recaptcha_pub_key}, 0, 0, {theme=>'white'} ) . '</td></tr></table>';
}

sub check
{
   my ($self, $f) = @_;
   return if $c->{captcha_mode} !~ /^(3|recaptcha)$/i;
   Captcha::reCAPTCHA->new->check_answer($c->{recaptcha_pri_key}, $ses->getIP, 
         $f->{recaptcha_challenge_field}, $f->{recaptcha_response_field},
   )->{is_valid};
}

1;
