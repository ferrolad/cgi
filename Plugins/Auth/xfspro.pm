package Plugins::Auth::xfspro;
use strict;
use vars qw($ses $db);

use XFileConfig;
use MIME::Base64;
use PBKDF2::Tiny;

sub checkLoginPass
{
   my ($self, $login, $pass) = @_;

   my $user = $db->SelectRow("SELECT * FROM Users WHERE usr_login=? AND !usr_social", $login) || return;

   if($user->{usr_password} =~ /^sha256:/)
   {
      my ($algo, $turns, $salt, $data) = split(/:/, $user->{usr_password});
      return $user if PBKDF2::Tiny::verify( decode_base64($data), 'SHA-256', $pass, decode_base64($salt), $turns );
   }
   else
   {
      # Legacy passwords
      my $check_pass = $db->SelectOne("SELECT DECODE(usr_password, ?) FROM Users WHERE usr_id=?", $c->{pasword_salt}, $user->{usr_id});
      return $user if $check_pass eq  $pass;
   }
}

1;
