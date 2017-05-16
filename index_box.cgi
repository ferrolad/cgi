#!/usr/bin/perl
### SibSoft.net ###
use strict;
use lib '.';
use XFileConfig;
use Session;
use CGI::Carp qw(fatalsToBrowser);

$c->{ip_not_allowed}=~s/\./\\./g;
if($c->{ip_not_allowed} && $ENV{REMOTE_ADDR}=~/$c->{ip_not_allowed}/)
{
   print"Content-type:text/html\n\n";
   print"Your IP was banned by administrator";
   exit;
}

my $ses = Session->new();
my $f = $ses->f;
my $op = $f->{op};

my $db= $ses->db;
&CheckAuth() unless $op eq 'login';

my $utype = $ses->getUser ? ($ses->getUser->{premium} ? 'prem' : 'reg') : 'anon';

$c->{$_}=$c->{"$_\_$utype"} for qw(max_upload_files
                                   disk_space
                                   max_upload_filesize
                                   download_countdown
                                   max_downloads_number
                                   captcha
                                   ads
                                   bw_limit
                                   remote_url
                                   direct_links
                                   down_speed
                                   max_rs_leech
                                   add_download_delay
                                   max_download_filesize
                                   torrent_dl
                                   torrent_dl_slots
                                   video_embed
                                   flash_upload);

&UploadResult if $f->{op} eq 'upload_result';
&UploadForm;

##############################

sub UploadForm
{
   my $server = $db->SelectRow("SELECT * FROM Servers 
                                WHERE srv_status='ON' 
                                AND srv_disk+? <= srv_disk_max
                                ORDER BY srv_last_upload 
                                LIMIT 1",$c->{max_upload_filesize}||100);

   $ses->message("We're sorry, there are no servers available for upload at the moment.<br>Refresh this page in some minutes.") unless $server;
   $server->{srv_htdocs_url}=~s/\/(\w+)$//;
   $server->{srv_tmp_url} = "$server->{srv_htdocs_url}/tmp";

   $ses->{form}->{no_hdr}=1;
   my $bg  = $f->{xbg}=~/^\w+$/i ? $f->{xbg} : 'FFFFFF';
   my $txt = $f->{xtxt}=~/^\w+$/i ? $f->{xtxt} : 'FFFFFF';
   $ses->PrintTemplate("upload_form_box.html",
                       'ext_allowed'      => $c->{ext_allowed},
                       'ext_not_allowed'  => $c->{ext_not_allowed},
                       'max_upload_files' => $c->{max_upload_files},
                       'max_upload_filesize' => $c->{max_upload_filesize},

                       'srv_cgi_url'      => $server->{srv_cgi_url},
                       'srv_tmp_url'      => $server->{srv_tmp_url},
                       'srv_htdocs_url'   => $server->{srv_htdocs_url},

                       'sess_id'          => $ses->getCookie( $ses->{auth_cook} ),
                       'utype'            => $utype,
                       'bg'               => $bg,
                       'txt'              => $txt,
                      );
}

sub UploadResult
{
   my $fnames      = &ARef($f->{'fn'});
   my $status      = &ARef($f->{'st'});

   my @arr;exit if $c->{site_url}!~/\/\/(www\.|)$ses->{dc}/i || !$ses->{dc};
   
   for(my $i=0;$i<=$#$fnames;$i++)
   {
      $fnames->[$i] = $ses->SecureStr($fnames->[$i]);
      $status->[$i] = $ses->SecureStr($status->[$i]);
      unless($status->[$i] eq 'OK')
      {
          push @arr, {file_name => $fnames->[$i],'error' => " $status->[$i]"};
          next;
      }
      my $file = $db->SelectRow("SELECT f.*, s.srv_htdocs_url
                                 FROM Files f, Servers s
                                 WHERE f.file_code=?
                                 AND f.srv_id=s.srv_id
                                 AND f.file_created > NOW()-INTERVAL 555 MINUTE",$fnames->[$i]);
      next unless $file;
      $file->{file_size2} = $file->{file_size};
      $file->{file_size} = $ses->makeFileSize($file->{file_size});
      $file->{download_link} = $ses->makeFileLink($file);
      $file->{delete_link} = "$file->{download_link}?killcode=$file->{file_del_id}";
      if($c->{m_i} && $file->{file_name}=~/\.(jpg|jpeg|gif|png|bmp)$/i)
      {
         my $ext=$1;
         my $iurl = $file->{srv_htdocs_url};
         $iurl=~s/^(.+)\/.+$/$1\/i/;
         my $dx = sprintf("%05d",($file->{file_real_id}||$file->{file_id})/$c->{files_per_folder});
         $file->{image_link} = "$iurl/$dx/$file->{file_real}.$ext";
         $file->{thumb_link} = "$iurl/$dx/$file->{file_real}_t.jpg";
      }
      push @arr, $file;
   }
   $ses->{form}->{no_hdr}=1;
   my $bg  = $f->{xbg}=~/^\w+$/i ? $f->{xbg} : 'FFFFFF';
   my $txt = $f->{xtxt}=~/^\w+$/i ? $f->{xtxt} : 'FFFFFF';
   $ses->PrintTemplate("upload_results_box.html",
                       'links' => \@arr,
                       'bg'    => $bg,
                       'txt'   => $txt,
                      );
}

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
     return undef;
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

sub ARef
{
  my $data=shift;
  $data=[] unless $data;
  $data=[$data] unless ref($data) eq 'ARRAY';
  return $data;
}
