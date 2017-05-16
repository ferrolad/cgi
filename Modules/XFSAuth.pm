package XFSAuth;
sub CheckAuth
{
  my $sess_id = $ses->getCookie( $ses->{auth_cook} );
  return undef unless $sess_id;
  return undef if $f->{id}&&!$ses->{dc};
  $ses->{user} = $db->SelectRow("SELECT u.*,
                                        UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec,
                                        UNIX_TIMESTAMP()-UNIX_TIMESTAMP(last_time) as dtt
                                 FROM Users u, Sessions s 
                                 WHERE s.session_id=? 
                                 AND s.usr_id=u.usr_id",$sess_id);
  unless($ses->{user})
  {
     sleep 1;
     return undef;
  }
  if($ses->{user}->{usr_status} eq 'BANNED')
  {
     delete $ses->{user};
     $ses->message("Your account was banned by administrator.");
  }
  if($ses->{user}->{dtt}>30)
  {
     $db->Exec("UPDATE Sessions SET last_time=NOW() WHERE session_id=?",$sess_id);
     $db->Exec("UPDATE Users SET usr_lastlogin=NOW(), usr_lastip=INET_ATON(?) WHERE usr_id=?", $ses->getIP, $ses->{user}->{usr_id} );
  }
  $ses->{user}->{premium}=1 if $ses->{user}->{exp_sec}>0;
  if($c->{m_d} && $ses->{user}->{usr_mod})
  {
      $ses->{lang}->{usr_mod}=1;
      $ses->{lang}->{m_d_f}=$c->{m_d_f};
      $ses->{lang}->{m_d_a}=$c->{m_d_a};
      $ses->{lang}->{m_d_c}=$c->{m_d_c};
  }
  #$ses->setCookie( $ses->{auth_cook} , $sess_id );
  return $ses->{user};
}

1;
