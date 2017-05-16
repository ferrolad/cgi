package Plugins::Captcha::solvemedia;
use XFileConfig;
use WWW::SolveMedia;

my @auth_data = ($c->{solvemedia_challenge_key},
                            $c->{solvemedia_verification_key},
                            $c->{solvemedia_authentication_key});

sub generate
{
   my ($self) = @_;
   return if $c->{captcha_mode} !~ /^(4|solvemedia)$/i;
   return "<center>" . WWW::SolveMedia->new( @auth_data )->get_html(undef,
                                undef,
                                {
                                  theme => lc($c->{solvemedia_theme}),
                                  size => lc($c->{solvemedia_size}),
                                }) . "</center>";
}

sub check
{
   my ($self, $f) = @_;
   return if $c->{captcha_mode} !~ /^(4|solvemedia)$/i;
   WWW::SolveMedia->new( @auth_data )->check_answer($ses->getIP, $f->{adcopy_challenge}, $f->{adcopy_response},
   )->{is_valid};
}

1;
