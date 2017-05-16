package Plugins::Auth::xfspro;
use strict;
use PBKDF2::Tiny;
use MIME::Base64;
use vars qw($ses $db $c);

sub checkLoginPass
{
   my ($self, $login, $pass) = @_;

   my $user = $db->SelectRow("SELECT *, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec
      FROM Users
      WHERE usr_login=?
      AND !usr_social",
      $login);

   my $answer = $user->{usr_password} =~ /^sha256:/
      ? _check_password_pbkdf2($pass, $user->{usr_password})
      : _check_password_legacy($pass, $user->{usr_id});

   return $user if $answer;
}

sub _check_password_pbkdf2
{
   my ($actual_pass, $hashed_pass) = @_;
   my ($algo, $salt, $data) = split(/:/, $hashed_pass);
   return PBKDF2::Tiny::verify( decode_base64($data), 'SHA-256', $actual_pass, decode_base64($salt), 1000 );
}

sub _check_password_legacy
{
   my ($actual_pass, $usr_id) = @_;
   return $db->SelectOne("SELECT usr_id FROM Users
      WHERE usr_id=?
      AND usr_password=ENCODE(?, ?)",
      $usr_id,
      $actual_pass,
      $c->{pasword_salt});
}

1;
