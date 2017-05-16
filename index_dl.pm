package index_dl;

use strict;
use XFileConfig;
use Session;
use CGI::Carp qw(fatalsToBrowser);
use URI::Escape;
use List::Util qw(max);
use XUtils;

$SIG{__WARN__} = sub {};

$c->{no_session_exit}=1;
my $ses;
my $f;
my $db;

sub run
{
   my ($query) = @_;
   $c->{ip_not_allowed}=~s/\./\\./g;
   if($c->{ip_not_allowed} && $ENV{REMOTE_ADDR}=~/^($c->{ip_not_allowed})$/)
   {
      print"Content-type:text/html\n\n";
      print"Your IP was banned by administrator";
      return;
   }

   $ses = Session->new($query);
   return if $ses->{error};

   $f = $ses->f;
   return $ses->message($c->{maintenance_full_msg}||"The website is under maintenance.","Site maintenance") if $c->{maintenance_full};

   $db ||= $ses->db;

   XUtils::CheckAuth($ses);

   if($ENV{HTTP_CGI_AUTHORIZATION} && $ENV{HTTP_CGI_AUTHORIZATION} =~ s/basic\s+//i)
   {
      &Login;
      return print"Content-type:text/html\n\n$ses->{error}" unless $ses->{user};
   }

   $ses->{utype} = $ses->getUser ? ($ses->getUser->{premium} ? 'prem' : 'reg') : 'anon';
   $ses->{lang}->{dmca_agent} = $ses->getUser && $ses->getUser->{usr_dmca_agent} ? 1 : 0;
   $ses->{lang}->{approve_count} = $db->SelectOne("SELECT COUNT(*) FROM Files WHERE file_awaiting_approve") if $ses->getUser && ($ses->getUser->{usr_mod} || $ses->getUser->{usr_adm});
   $ses->{lang}->{del_confirm_request_count} = $db->SelectOne("SELECT COUNT(*) FROM Misc WHERE name='mass_del_confirm_request'") if $ses->getUser && $ses->getUser->{usr_adm};
   
   &ImportUserLimits();
   
   my $sub={
       download1     => \&Download1,
       download2     => \&Download2,
       video_embed   => \&VideoEmbed,
       video_embed2  => \&VideoEmbed2,
       mp3_embed     => \&Mp3Embed,
       mp3_embed2    => \&Mp3Embed2,
       deurl         => \&DeURL,
   
            }->{ $f->{op} };
   return &$sub() if $sub;
   
   return $ses->redirect($c->{site_url});
}

###################################

sub ImportUserLimits
{
   $c->{$_}=$c->{"$_\_$ses->{utype}"} for qw(max_upload_files
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
                                      torrent_fallback_after
                                      video_embed
                                      mp3_embed
                                      flash_upload
                                      file_dl_delay
                                      rar_info
                                      download_on 
                                      m_n_limit_conn
                                      m_n_dl_resume
                                      );
}

sub Login
{
  ($f->{login}, $f->{password}) = split(':',$ses->decode_base64($ENV{HTTP_CGI_AUTHORIZATION}));
  $ses->{user} = $db->SelectRow("SELECT *, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec 
                                 FROM Users 
                                 WHERE usr_login=? 
                                 AND usr_password=ENCODE(?,?)", $f->{login}, $f->{password}, $c->{pasword_salt} );
  unless($ses->{user})
  {
     $ses->{error}="Invalid user";
     return undef;
  }
  
  $ses->{user}->{premium}=1 if $ses->{user}->{exp_sec}>0;
  if($ses->{user}->{usr_status} eq 'PENDING')
  {
     delete $ses->{user};
     $ses->{error}="Account not confirmed";
     return;
  }
  if($ses->{user}->{usr_status} eq 'BANNED')
  {
     delete $ses->{user};
     $ses->{error}="Banned account";
     return;
  }
};

sub getMaxDLSize
{
   my ($owner) = @_;
   my $usr_aff_max_dl_size = $owner->{usr_aff_max_dl_size} if $owner && $owner->{usr_aff_enabled} && $ses->{utype} ne 'prem';
   return $usr_aff_max_dl_size || $c->{max_download_filesize};
}

sub AsPremium
{
   my ($file) = @_;
   $db->Exec("UPDATE Users SET usr_premium_traffic=GREATEST(usr_premium_traffic - ?, 0) WHERE usr_id=?",
      $file->{file_size},
      $ses->getUserId);

   $ses->{utype} = 'prem';
   $ses->getUser()->{premium} = 1;
   $ses->getUser()->{usr_direct_downloads} = 1;
   &ImportUserLimits();
}

sub CheckHasPremiumTraffic
{
   my $user = $ses->getUser() if $ses->getUser();
   return 1 if $user && !$user->{premium} && $user->{usr_premium_traffic} > 0;
}

sub DownloadChecks
{
   my ($file) = @_;

   my $owner = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $file->{usr_id});
   my $max_dl_size = &getMaxDLSize($owner);

   if($max_dl_size && $file->{file_size} > $max_dl_size*1048576)
   {
      $file->{message} = "You can download files up to $max_dl_size Mb only.<br>Upgrade your account to download bigger files.";
   }

   if($c->{max_downloads_number} && $file->{file_downloads} >= $c->{max_downloads_number})
   {
      $file->{message} = "This file reached max downloads limit";
   }

   if($c->{file_dl_delay})
   {
      my $cond = $ses->getUser ? "usr_id=".$ses->getUserId : "ip=INET_ATON('".$ses->getIP."')";
      my $last = $db->SelectRow("SELECT *, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(created) as dt 
                                 FROM IP2Files WHERE $cond 
                                 ORDER BY created DESC LIMIT 1");
      my $wait = $c->{file_dl_delay} - $last->{dt};
      if($last->{dt} && $wait>0)
      {
         require Time::Elapsed;
         my $et = new Time::Elapsed;
         my $elapsed = $et->convert($wait);
         $file->{message}  = "You have to wait $elapsed till next download";
         $file->{message} .= "<br><br>Download files instantly with <a href='$c->{site_url}/?op=payments'>Premium-account</a>" if $c->{enabled_prem};
      }
   }

   if($c->{add_download_delay})
   {
      my $cond = $ses->getUser ? "usr_id=".$ses->getUserId : "ip=INET_ATON('".$ses->getIP."')";
      my $last = $db->SelectRow("SELECT *, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(created) as dt 
                                 FROM IP2Files WHERE $cond 
                                 ORDER BY created DESC LIMIT 1");
      my $wait = int($c->{add_download_delay}*$last->{size}/(100*1048576)) - $last->{dt};
      if($wait>0)
      {
         require Time::Elapsed;
         my $et = new Time::Elapsed;
         my $elapsed = $et->convert($wait);
         $file->{message}  = "You have to wait $elapsed till next download";
         $file->{message} .= "<br><br>Download files instantly with <a href='$c->{site_url}/?op=payments'>Premium-account</a>" if $c->{enabled_prem};
      }
   }

   if($ses->getUserLimit('bw_limit'))
   {
      $file->{message} = "You have reached the download-limit: $c->{bw_limit} Mb for last $c->{bw_limit_days} days"
         if $ses->getUserBandwidth($c->{bw_limit_days}) > $ses->getUserLimit('bw_limit');
   }

   if($file->{file_premium_only} && $ses->{utype} ne 'prem')
   {
      $ses->PrintTemplate("download_premium_only.html",%$file);
      exit;
   }

   return $file;
}

sub Download0
{
   my ($file) = @_;
   if($c->{pre_download_page_alt})
   {
      my @arr = split(/,/,$c->{payment_plans});
      $file->{free_download} = 1;
      use Data::Dumper qw(Dumper);
      my @payment_types = $ses->getPlugins('Payments')->get_payment_buy_with;

      my @plans =  @{ $ses->ParsePlans($c->{payment_plans}, 'array') };
      for(@plans)
      {
         $_->{payment_types} = \@payment_types;
      }

      my @traffic_packages =  @{ $ses->ParsePlans($c->{traffic_plans}, 'array') };
      for(@plans, @traffic_packages)
      {
         $_->{payment_types} = \@payment_types;
      }

      return $ses->PrintTemplate("download0_alt.html", 
                                 %{$file},
                                 %{$c},
                                 'plans'         => \@plans,
                                 'rand' => $ses->randchar(6),
                                 #%cc,
                                 'referer' => $f->{referer},
                                 'currency_symbol' => $c->{currency_symbol}||'$',
                                 'ask_email' => $ses->{utype} eq 'anon' && !$c->{no_anon_payments},
                                 'traffic_packages' => \@traffic_packages,
                                 );
   }

   my %cc = %$c;
   for my $x ('max_upload_filesize')
   {
      for my $y ('anon','reg','prem')
      {
         my $z = "$x\_$y";
         $cc{$z} = $cc{$z} ? "$cc{$z} Mb" : "No limits";
      }
   }
   $cc{max_downloads_number_reg}||='Unlimited';
   $cc{max_downloads_number_prem}||='Unlimited';
   $cc{files_expire_anon} = $cc{files_expire_access_anon} ? "$cc{files_expire_access_anon} $ses->{lang}->{lang_days_after_downl}" : $ses->{lang}->{lang_never};
   $cc{files_expire_reg}  = $cc{files_expire_access_reg}  ? "$cc{files_expire_access_reg} $ses->{lang}->{lang_days_after_downl}" : $ses->{lang}->{lang_never};
   $cc{files_expire_prem} = $cc{files_expire_access_prem} ? "$cc{files_expire_access_prem} $ses->{lang}->{lang_days_after_downl}" : $ses->{lang}->{lang_never};

   $cc{disk_space_reg} = $cc{disk_space_reg} ? sprintf("%.0f GB",$cc{disk_space_reg}/1024) : "No limit";
   $cc{disk_space_prem} = $cc{disk_space_prem} ? sprintf("%.0f GB",$cc{disk_space_prem}/1024) : "No limit";

   $cc{bw_limit_anon} = $cc{bw_limit_anon} ? sprintf("%.0f GB",$cc{bw_limit_anon}/1024)." in $cc{bw_limit_days} $ses->{lang}->{lang_days}" : 'Unlimited';
   $cc{bw_limit_reg}  = $cc{bw_limit_reg}  ? sprintf("%.0f GB",$cc{bw_limit_reg}/1024)." in $cc{bw_limit_days} $ses->{lang}->{lang_days}" : 'Unlimited';
   $cc{bw_limit_prem} = $cc{bw_limit_prem} ? sprintf("%.0f GB",$cc{bw_limit_prem}/1024)." in $cc{bw_limit_days} $ses->{lang}->{lang_days}" : 'Unlimited';

   print "Strict-Transport-Security: max-age=0;includeSubDomains;\n";

   return $ses->PrintTemplate("download0.html", 
                              %{$file},
                              %cc,
                              'referer' => $f->{referer} );
}

sub Download1
{

   return $ses->message($c->{maintenance_download_msg}||"Downloads are temporarily disabled due to site maintenance","Site maintenance") if $c->{maintenance_download};
   return $ses->redirect("$c->{site_url}/?op=login&redirect=$f->{id}") if !$c->{download_on} && !$ses->getUserId;
   return $ses->message("Downloads are disabled for your user type","Download error") if !$c->{download_on};

   if($c->{download_disabled_countries} && -f "$c->{cgi_path}/GeoIP.dat")
   {
      require Geo::IP;
      my $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
      my $country = $gi->country_code_by_addr($ses->getIP);
      for(split(/\s*\,\s*/,$c->{download_disabled_countries}))
      {
          return $ses->message("Downloads are disabled for your country: $country") if $_ eq $country;
      }
   }

   if($c->{mask_dl_link} && $ENV{REQUEST_URI} !~ /download$/)
   {
      $ses->setCookie('file_code', $f->{id}, '+1h');
      return $ses->redirect("$c->{site_url}/download");
   }
   else
   {
      $f->{id} ||= $ses->getCookie('file_code');
   }

   my ($fname) = $ENV{QUERY_STRING}=~/&fname=(.+)$/;
   $fname||=$f->{fname};
   $fname=~s/\.html?$//i;
   $fname=~s/\///;
   $fname=~s/\?.+$//;
   $f->{referer}||=$ENV{HTTP_REFERER};

   # Do not accept referers with the same domain
   $ses->setCookie('ref_url', $f->{referer}, '+1d')
      if $ses->getDomain($f->{referer}) ne $ses->getDomain($c->{site_url});

   my $sql = "SELECT f.*, s.*,
      u.usr_login as file_usr_login,
      u.usr_profit_mode,
      DATE(file_created) as created_date,
      DATE_FORMAT( file_created, '%H:%i:%S') as created_time
              FROM (Files f, Servers s)
              LEFT JOIN Users u ON f.usr_id = u.usr_id
              WHERE f.file_code=?
              AND f.srv_id=s.srv_id
              AND file_trashed=0
              AND file_awaiting_approve=0";

   my $file = $db->SelectRowCached('file', $sql, $f->{id});

   my $fname2 = lc $file->{file_name} if $file;
   $fname=~s/\s/_/g;
   $fname2=~s/\s/_/g;
   $fname=~s/\.\w{2,5}$//;$fname=~s/\.\w{2,5}$//;
   $fname2=~s/\.\w{2,5}$//;$fname2=~s/\.\w{2,5}$//;
   return $ses->message("No such file with this filename") if $file && $fname && $fname2 ne lc uri_unescape($fname);
   return $ses->redirect("$c->{site_url}/?op=del_file&id=$f->{id}&del_id=$1") if $ENV{REQUEST_URI}=~/\?killcode=(\w+)$/i;

   my $reason;
   unless($file)
   {
      $reason = $db->SelectRow("SELECT * FROM DelReasons WHERE file_code=?",$f->{id});
      $db->Exec("UPDATE DelReasons SET last_access=NOW() WHERE file_code=?",$reason->{file_code}) if $reason;
   }

   $fname=$file->{file_name} if $file;
   $fname=$reason->{file_name} if $reason;
   $fname=~s/[_\.-]+/ /g;
   $fname=~s/([a-z])([A-Z][a-z])/$1 $2/g;
   my @fn = grep{length($_)>2 && $_!~/(www|net|ddl)/i}split(/[\s\.]+/, $fname);
   $ses->{page_title} = $ses->{lang}->{lang_download}." ".join(' ',@fn);
   $ses->{meta_descr} = $ses->{lang}->{lang_download_file}." ".join(' ',@fn);
   $ses->{meta_keywords} = lc join(', ',@fn);

   return $ses->PrintTemplate("download1_deleted.html",%$reason) if $reason;
   return $ses->PrintTemplate("download1_no_file.html") unless $file;

   return $ses->message("This server is in maintenance mode. Refresh this page in some minutes.") if $file->{srv_status} eq 'OFF';

   &AsPremium($file) if &CheckHasPremiumTraffic();
   my $premium = $ses->getUser && $ses->getUser->{premium};

   $file->{fsize} = $ses->makeFileSize($file->{file_size});
   $file->{download_link} = $ses->makeFileLink($file);

   $c->{ads}=0 if $c->{bad_ads_words} && ($file->{file_name}=~/$c->{bad_ads_words}/is || $file->{file_descr}=~/$c->{bad_ads_words}/is);

   $f->{method_premium}=1 if $premium;
   my $skip_download0=1 if $c->{m_i} && $file->{file_name}=~/\.(jpg|jpeg|gif|png|bmp)$/i && $file->{file_size}<1048576*5;
   if(!$skip_download0 && !$f->{method_free} && !$f->{method_premium} && $c->{pre_download_page} && $c->{enabled_prem})
   {
      return Download0($file);
   }
   else
   {
     return $ses->redirect("$c->{site_url}/?op=payments") if $f->{method_premium} && !$ses->getUser;
     return $ses->redirect("$c->{site_url}/?op=payments") if $f->{method_premium} && !$premium;
   }

   &Download2('no_checks') if  $premium &&
                               !$c->{captcha} &&
                               !$c->{download_countdown} &&
                               !$file->{file_password} &&
                               $ses->getUser->{usr_direct_downloads};

   if($file->{usr_id})
   {
      $ses->setCookie("aff",$file->{usr_id},'+14d');
   }

   $file = &DownloadChecks($file);

   my %secure = $ses->SecSave( $file->{file_id}, $c->{download_countdown} );

   $file->{file_password}='' if $ses->getUser && $ses->getUser->{usr_adm};
   $file->{file_descr}=~s/\n/<br>/gs;

   my $enable_file_comments=1 if $c->{enable_file_comments};
   $enable_file_comments=0 if $c->{comments_registered_only} && !$ses->getUser;
   if($enable_file_comments)
   {
      $file->{comments} = &CommentsList(1,$file->{file_id});
   }
   if($c->{show_more_files})
   {
      my $more_files = $db->SelectARef("SELECT file_code,file_name,file_size
                                        FROM Files 
                                        WHERE usr_id=?
                                        AND file_public=1
                                        AND file_created>?-INTERVAL 3 HOUR
                                        AND file_created<?+INTERVAL 3 HOUR
                                        AND file_id<>?
                                        LIMIT 20",$file->{usr_id},$file->{file_created},$file->{file_created},$file->{file_id});
      for(@$more_files)
      {
         $_->{file_size} = $_->{file_size}<1048576 ? sprintf("%.01f Kb",$_->{file_size}/1024) : sprintf("%.01f Mb",$_->{file_size}/1048576);
         $_->{download_link} = $ses->makeFileLink($_);
         $_->{file_name} =~ s/_/ /g;
      }
      $file->{more_files} = $more_files;
   }

   if($file->{file_name}=~/\.(jpg|jpeg|gif|png|bmp)$/i && $c->{m_i} && !$file->{file_password})
   {
      $ses->getThumbLink($file);
      $file->{image_url} ||= $ses->getPlugins('CDN')->genDirectLink($file); # No hotlinks mode
      $file->{no_link}=1 if $c->{image_mod_no_download};
      DownloadTrack($file) if $c->{image_mod_track_download};
   }

   $file->{forum_code} = $file->{thumb_url} ? "[URL=$file->{download_link}][IMG]$file->{thumb_url}\[\/IMG]\[\/URL]" : "[URL=$file->{download_link}]$file->{file_name} -  $file->{file_size}\[\/URL]";
   $file->{html_code} = $file->{thumb_url} ? qq[<a href="$file->{download_link}" target=_blank><img src="$file->{thumb_url}" border=0><\/a>] : qq[<a href="$file->{download_link}" target=_blank>$file->{file_name} - $file->{file_size}<\/a>];
   
   if($c->{mp3_mod} && $file->{file_name}=~/\.mp3$/i && !$file->{message})
   {
      DownloadTrack($file) if $c->{mp3_mod_no_download};
      $file->{song_url} = $ses->getPlugins('CDN')->genDirectLink($file, file_name => "$file->{file_code}.mp3")||return;
      (undef,$file->{mp3_secs},$file->{mp3_bitrate},$file->{mp3_freq},$file->{mp3_artist},$file->{mp3_title},$file->{mp3_album},$file->{mp3_year}) = split(/\|/,$file->{file_spec}) if $file->{file_spec}=~/^A\|/;
      $file->{mp3_album}='' if $file->{mp3_album} eq 'NULL';
      $file->{no_link}=1 if $c->{mp3_mod_no_download};
      $file->{mp3_mod_autoplay}=$c->{mp3_mod_autoplay};
      $ses->{meta_keywords}.=", $file->{mp3_artist}" if $file->{mp3_artist};
      $ses->{meta_keywords}.=", $file->{mp3_title}" if $file->{mp3_title};
      $ses->{meta_keywords}.=", $file->{mp3_album}" if $file->{mp3_album};
   }
   if($file->{file_name}=~/\.rar$/i && $file->{file_spec} && $c->{rar_info})
   {
      $file->{file_spec}=~s/\r//g;
      $file->{rar_nfo}="<b style='color:red'>$ses->{lang}->{rar_password_protected}<\/b>\n" if $file->{file_spec}=~s/password protected//ie;
      my $cmt=$1 if $file->{file_spec}=~s/\n\n(.+)$//s;
      my (@rf,$fld);
      while($file->{file_spec}=~/^(.+?) - ([\d\.]+) (KB|MB)$/gim)
      {
         my $fsize = "$2 $3";
         my $fname=$1;
         if($fname=~s/^(.+)\///)
         {
            push @rf,"<b>$1</b>" if $fld ne $1;
            $fld = $1;
         }
         else
         {
            $fld='';
         }
         $fname=" $fname" if $fld;
         push @rf, "$fname - $fsize";
      }
      $file->{rar_nfo}.=join "\n", @rf;
      $file->{rar_nfo}.="\n\n<i>$cmt</i>" if $cmt;
      $file->{rar_nfo}=~s/\n/<br>\n/g;
      $file->{rar_nfo}=~s/^\s/ &nbsp; &nbsp;/gm;
      
   }

   $file = &VideoMakeCode($file,$c->{m_v_page}==0)||return if $c->{m_v} && !$file->{message};
   $file->{embed_code} = $file->{video_embed_code} = 1 if $c->{video_embed} && $file->{file_spec}=~/^V/;
   $file->{embed_code} = $file->{mp3_embed_code} = 1 if $c->{mp3_embed} && $file->{file_name} =~ /\.mp3$/;

   DownloadTrack($file) if $file->{video_code} && $c->{video_mod_no_download};

   $file->{no_link}=1 if $file->{message};

   $file->{add_to_account}=1 if $ses->getUser && $file->{usr_id}!=$ses->getUserId && $file->{file_public} && !$file->{file_password};
   $file->{video_ads}=1 if $c->{m_a} && $c->{ads};
   ($file->{ext}) = $file->{file_name}=~/\.(\w{2,4})$/;
   $file->{ext}||='flv';
   $file->{flv}=1 if $file->{ext}=~/^flv|mp4$/i;

   if($c->{docviewer} && $file->{file_name} =~ /\.(pdf|ps|doc|docx|ppt|xls|xlsb|odt|odp|ods)$/)
   {
     my $direct_link = $ses->getPlugins('CDN')->genDirectLink($file,
                        file_name => "$file->{file_code}.$1",
                        link_ip_logic => 'all',
                        dl_method => 'cgi');
     $file->{docviewer_url} = "https://docs.google.com/gview?url=$direct_link&embedded=true";
     $file->{no_link}=1 if $c->{docviewer_no_download};
   }

   my @payment_types = $ses->getPlugins('Payments')->get_payment_buy_with;

   my $file_traffic = $file->{file_downloads} * $file->{file_size};
   $file->{bittorrent} = 1 if $c->{torrent_fallback_after} &&  $file_traffic > $c->{torrent_fallback_after} * 2**30;

   $file->{file_name} = &shorten($file->{file_name}, 50);

   sub shorten
   {
      my ($str, $max_length) = @_;
      $max_length ||= $c->{display_max_filename};
      return length($str)>$max_length ? substr($str,0,$max_length).'&#133;' : $str
   }

   print "Strict-Transport-Security: max-age=0;includeSubDomains;\n";

   return $ses->PrintTemplate("download1.html",
                       %{$file},
                       %{$c},
                       'payment_types' => \@payment_types,
                       'plans'         => $ses->ParsePlans($c->{payment_plans}, 'array'),
                       'msg'           => $f->{msg}||$file->{message},
                       'site_name'     => $c->{site_name},
                       'pass_required' => $file->{file_password} && 1,
                       'countdown'     => $c->{download_countdown},
                       'direct_links'  => $c->{direct_links},
                       'premium'       => $premium,
                       'method_premium'=> $f->{method_premium},
                       'method_free'   => $f->{method_free},
                       'referer'       => $f->{referer},
                       'cmt_type'      => 1,
                       'cmt_ext_id'    => $file->{file_id},
                       'rnd1'          => $ses->randchar(6),
                       %secure,
                       'enable_file_comments' => $enable_file_comments,
                       'token'      => $ses->genToken(op => 'admin_files'),
                      );
}

sub Download2
{
   my $no_checks = shift;
   return $ses->message($c->{maintenance_download_msg}||"Downloads are temporarily disabled due to site maintenance","Site maintenance") if $c->{maintenance_download};
   my $usr_id = $ses->getUser ? $ses->getUserId : 0;
   my $file = $db->SelectRow("SELECT *, INET_NTOA(file_ip) as file_ip, u.usr_profit_mode
                              FROM (Files f, Servers s)
                              LEFT JOIN Users u ON f.usr_id = u.usr_id 
                              WHERE f.file_code=? 
                              AND f.srv_id=s.srv_id",$f->{id});
   return $ses->message("No such file") unless $file;
   $c->{ads}=0 if $c->{bad_ads_words} && ($file->{file_name}=~/$c->{bad_ads_words}/is || $file->{file_descr}=~/$c->{bad_ads_words}/is);
   my $premium = $usr_id && $ses->getUser->{premium};

   if($f->{dl_torrent})
   {
      my $file_name_encoded = URI::Escape::uri_escape($file->{file_name});
      my $dx = sprintf("%05d",($file->{file_real_id}||$file->{file_id})/$c->{files_per_folder});
      my $url = "http://$1:9091/transmission/rpc?method=start_seeding&dx=$dx&file_real=$file->{file_real}&file_name=$file_name_encoded" if $file->{srv_htdocs_url} =~ /^https?:\/\/([^\/:]+)/;
      use LWP::UserAgent;
      my $torrent = LWP::UserAgent->new->get($url);
      my $torrent_file_name = "[$c->{site_name}] $file->{file_name}.torrent";
      print "Content-Disposition: attachment; filename=\"$torrent_file_name\"\n";
      print "Content-type: application/attachment\n\n";
      print $torrent->decoded_content;
      exit;
   }

   unless($no_checks)
   {
      return $ses->redirect("$c->{site_url}/?op=login&redirect=$f->{id}") if !$c->{download_on} && !$ses->getUserId;
      return $ses->message("Downloads are disabled for your user type","Download error") if !$c->{download_on};
      return &UploadForm unless $ENV{REQUEST_METHOD} eq 'POST';
      return &Download1 unless $ses->SecCheck( $f->{'rand'}, $file->{file_id}, $f->{code} );
      if($file->{file_password} && $file->{file_password} ne $f->{password} && !($ses->getUser && $ses->getUser->{usr_adm}))
      {
         $f->{msg} = 'Wrong password';
         return &Download1;
      }
   }

   $file = &DownloadChecks($file);

   return $ses->message($file->{message}) if $file->{message};

   $file->{fsize} = $ses->makeFileSize($file->{file_size});
   
   my $speed = $c->{down_speed};
   $speed *= 2 if &happyHours();

   $file->{direct_link} = $ses->getPlugins('CDN')->genDirectLink($file, speed => $speed);
   return $ses->message("Couldn't generate direct link") if !$file->{direct_link};

   DownloadTrack($file);

   if($no_checks && $ses->getUser && $ses->getUser->{usr_direct_downloads})
   {
      print("Content-type:text/plain\n\n$file->{direct_link}"), exit() if $c->{selenium_directlinks};
      return $ses->redirect($file->{direct_link}) 
   }

   return $ses->redirect($file->{direct_link}) if $no_checks && $ses->getUser && $ses->getUser->{usr_direct_downloads};
   return $ses->redirect($file->{direct_link}) if !$c->{show_direct_link} && !$c->{adfly_uid};

   $file->{direct_link2} = "http://adf.ly/$c->{adfly_uid}/$file->{direct_link}" if $c->{adfly_uid} && $ses->{utype} ne 'prem';

   $file = &VideoMakeCode($file,$c->{m_v_page}==1)||return if $c->{m_v};
   $file->{video_ads}=1 if $c->{m_a} && $c->{ads};

   print "Strict-Transport-Security: max-age=0;includeSubDomains;\n";

   return $ses->PrintTemplate("download2.html",
                       %{$file},
                       %$c,
                       'symlink_expire'   => $c->{symlink_expire},
                      );
}

sub happyHours
{
   my @hours = split(/,/, $c->{happy_hours});
   my $hour = sprintf("%02d", (getTime(time))[3]);
   return 1 if grep { $_ eq $hour } @hours;
}

sub VideoMakeCode
{
   my ($file,$gen) = @_;
   my ($ext) = $file->{file_name}=~/\.(\w+)$/i;

   return $file if $file->{file_name} !~ /\.(avi|divx|xvid|mpg|mpeg|vob|mov|3gp|flv|mp4|wmv|mkv)$/i;

   $file->{no_link}=1 if $c->{video_mod_no_download};

   # Parsing file_spec
   my @fields=qw(vid vid_length vid_width vid_height vid_bitrate vid_audio_bitrate vid_audio_rate vid_codec vid_audio_codec vid_fps);
   my @vinfo = split(/\|/,$file->{file_spec});
   $file->{$fields[$_]}=$vinfo[$_] for (0..$#fields);

   # Thumbs
   my $dx = sprintf("%05d",($file->{file_real_id}||$file->{file_id})/$c->{files_per_folder});
   $file->{srv_htdocs_url}=~/(.+)\/.+$/;
   $file->{video_img_url}="$1/i/$dx/$file->{file_real}.jpg";
   $file->{video_thumb_url}="$1/i/$dx/$file->{file_real}_t.jpg";

   # Dimensions
   ($file->{vid_width},$file->{vid_height})=($c->{m_v_width},$c->{m_v_height}) if $c->{m_v_width} && $c->{m_v_height};
   $file->{vid_width}=$f->{w} if $f->{w};
   $file->{vid_height}=$f->{h} if $f->{h};
   $file->{vid_height2} = $file->{vid_height}+20;
   $file->{vid_length2} = sprintf("%02d:%02d:%02d",int($file->{vid_length}/3600),int(($file->{vid_length}%3600)/60),$file->{vid_length}%60);

   return $file unless $gen;

   # Direct link
   $ext = 'mp4' if $file->{file_size_encoded};
   my $direct_link = $ses->getPlugins('CDN')->genDirectLink($file,
      encoded => 1,
      file_name => "video.$ext",
      accept_ranges => 1,
      limit_conn => max( $c->{m_n_limit_conn}, 10 ));
   return if !$direct_link;
   $file->{video_code} = $ses->getPlugins('Video')->makeCode($file, $direct_link);

   # Ads overlay mod
   if($c->{m_a} && $file->{video_code})
   {
      $file->{m_a_css}="document.write('<Style>#player_img {position:absolute;}
a#vid_play {background: repeat scroll center top; display:block; position:absolute; top:50%; margin-top:-30px; left:15%; margin-left:-30px; z-index: 99; width: 60px; height: 60px;}
a#vid_play:hover {background-position:bottom;}
#player_ads {position:absolute; top:0px; left:30%; width:70%; height:100%; z-index:2;}
#player_code {visibility: hidden;}</Style>');";
      $file->{m_a_css} = $ses->encodeJS($file->{m_a_css});
   }

   return $file;
}

sub VideoEmbed
{
   #print"Content-type:text/html\n\n";
   return print("Content-type:text/html\n\nVideo mod is disabled") unless $c->{m_v};
   my $sql = "SELECT f.*, s.*, u.usr_id, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec
                              FROM (Files f, Servers s)
                              LEFT JOIN Users u ON f.usr_id = u.usr_id
                              WHERE f.file_code=?
                              AND f.srv_id=s.srv_id";
   my $file = $db->SelectRowCached('file', $sql,$f->{file_code});
   return print("Content-type:text/html\n\nFile was deleted") unless $file;
   my $utype2 = $file->{usr_id} ? ($file->{exp_sec}>0 ? 'prem' : 'reg') : 'anon';
   return print("Content-type:text/html\n\nVideo embed restricted for this user") unless $c->{"video_embed_$utype2"};

   $file = &VideoMakeCode($file,1)||return;
   return print("Content-type:text/html\n\nCan't create video code") unless $file->{video_code};
   $file->{video_ads}=$c->{m_a};
   $ses->{form}->{no_hdr}=1;
   DownloadTrack($file) if $c->{m_y_embed_earnings};
   $db->Exec("UPDATE Files SET file_views=file_views+1 WHERE file_id=?",$file->{file_id});
   return $ses->PrintTemplate("video_embed.html",%$file,m_a_code => $c->{m_a_code});
}

sub VideoEmbed2
{
   return print("Content-type:text/html\n\nVideo mod is disabled") unless $c->{m_v};
   my $file = $db->SelectRow("SELECT f.*, s.*, u.usr_id, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec
                              FROM (Files f, Servers s)
                              LEFT JOIN Users u ON f.usr_id = u.usr_id
                              WHERE f.file_code=?
                              AND f.srv_id=s.srv_id",$f->{file_code});
   return print("Content-type:text/html\n\nFile was deleted") unless $file;
   my $utype2 = $file->{usr_id} ? ($file->{exp_sec}>0 ? 'prem' : 'reg') : 'anon';
   return print("Content-type:text/html\n\nVideo embed restricted for this user") unless $c->{"video_embed_$utype2"};

   my ($ext) = $file->{file_name}=~/\.(\w{2,4})$/;
   my $url = $ses->getPlugins('CDN')->genDirectLink($file, file_name => "video.$ext");
   $db->Exec("UPDATE Files SET file_views=file_views+1 WHERE file_id=?",$file->{file_id});
   return $ses->redirect($url);
}

sub Mp3Embed
{
   return print("Content-type:text/html\n\nmp3 embed disabled") unless $c->{mp3_embed};
   my $file = $db->SelectRow("SELECT f.*, s.*, u.usr_id, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec
                              FROM (Files f, Servers s)
                              LEFT JOIN Users u ON f.usr_id = u.usr_id
                              WHERE f.file_code=?
                              AND f.srv_id=s.srv_id",$f->{file_code});
   return print("Content-type:text/html\n\nnot allowed") if $file->{file_name} !~ /mp3$/;

   my $utype2 = $file->{usr_id} ? ($file->{exp_sec}>0 ? 'prem' : 'reg') : 'anon';
   return print("Content-type:text/html\n\nmp3 embed restricted for this user") unless $c->{"mp3_embed_$utype2"};

   $file->{song_url} = $ses->getPlugins('CDN')->genDirectLink($file, file_name => 'audio.mp3')||return;
   (undef,$file->{mp3_secs},$file->{mp3_bitrate},$file->{mp3_freq},$file->{mp3_artist},$file->{mp3_title},$file->{mp3_album},$file->{mp3_year}) = split(/\|/,$file->{file_spec}) if $file->{file_spec}=~/^A\|/;
   $file->{mp3_mod_autoplay}=$c->{mp3_mod_autoplay};

   $file->{download_url} = $ses->makeFileLink($file);

   DownloadTrack($file) if $c->{m_y_embed_earnings};

   $ses->{form}->{no_hdr}=1;
   $db->Exec("UPDATE Files SET file_views=file_views+1 WHERE file_id=?",$file->{file_id});
   return $ses->PrintTemplate("embed_mp3.html",%$file);
}

sub Mp3Embed2
{
   return print("Content-type:text/html\n\nmp3 embed disabled") unless $c->{mp3_mod_embed};
   my $file = $db->SelectRow("SELECT f.*, s.*, u.usr_id, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec
                              FROM (Files f, Servers s)
                              LEFT JOIN Users u ON f.usr_id = u.usr_id
                              WHERE f.file_code=?
                              AND f.srv_id=s.srv_id",$f->{file_code});
   return print("Content-type:text/html\n\nnot allowed") if $file->{file_name} !~ /mp3$/;

   my $utype2 = $file->{usr_id} ? ($file->{exp_sec}>0 ? 'prem' : 'reg') : 'anon';
   return print("Content-type:text/html\n\nmp3 embed restricted for this user") unless $c->{"mp3_embed_$utype2"};

   $file->{song_url} = $ses->getPlugins('CDN')->genDirectLink($file, file_name => 'audio.mp3')||return;
   $db->Exec("UPDATE Files SET file_views=file_views+1 WHERE file_id=?",$file->{file_id});
   return $ses->redirect($file->{song_url});
}

sub DownloadTrack
{
   my ($file) = @_;
   my $usr_id = $ses->getUser ? $ses->getUserId : 0;

   my $total_money_charged = 0;
   
   if(!$db->SelectOne("SELECT file_id FROM IP2Files WHERE file_id=? AND ip=INET_ATON(?) AND usr_id=?",$file->{file_id},$ses->getIP,$usr_id))
   {
      $f->{referer}||= $ses->getCookie('ref_url') || $ENV{HTTP_REFERER};
      $f->{referer}=~s/$c->{site_url}//i;
      $f->{referer}=~s/^http:\/\///i;

      if($c->{m_n_100_complete_percent})
      {
         # Don't charge any money, leave it for fs.cgi instead
         $db->Exec("INSERT INTO IP2Files SET 
               file_id=?, usr_id=?, owner_id=?, ip=INET_ATON(?), size=0, referer=?, status=?",      
               $file->{file_id},$usr_id||0,$file->{usr_id}||0,$ses->getIP,$f->{referer}||'',
               ($f->{adblock_detected} ? 'ADBLOCK' : 'Not completed'));
         return;
      }

      my ($money, $status);

      sub refuse
      {
         $status ||= shift;
         $money = 0;
      }

      refuse('ADBLOCK') if $f->{adblock_detected};
      refuse('GEOIP_MISSING') if $ses->iPlg('p') && ! -e "$c->{cgi_path}/GeoIP.dat";

      if($ses->iPlg('p') && -e "$c->{cgi_path}/GeoIP.dat")
      {
         my $size_id;
         my @ss = split(/\|/,$c->{tier_sizes});
         for(0..5){$size_id=$_ if defined $ss[$_] && $file->{file_size}>=$ss[$_]*1024*1024;}
         require Geo::IP;
         my $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
         my $country = $gi->country_code_by_addr($ses->getIP);
         if(defined $size_id)
         {
           my $tier_money = $c->{tier4_money};
           if   ($c->{tier1_countries} && $country=~/^($c->{tier1_countries})$/i){ $tier_money = $c->{tier1_money}; }
           elsif($c->{tier2_countries} && $country=~/^($c->{tier2_countries})$/i){ $tier_money = $c->{tier2_money}; }
           elsif($c->{tier3_countries} && $country=~/^($c->{tier3_countries})$/i){ $tier_money = $c->{tier3_money}; }
           $money = (split(/\|/,$tier_money))[$size_id];
           refuse('REWARD_NOT_SPECIFIED') if !$money;
         }

         refuse('MAX24_REACHED') if $c->{max_money_last24} && $db->SelectOne("SELECT SUM(money) FROM IP2Files WHERE ip=INET_ATON(?) AND created>NOW()-INTERVAL 24 HOUR",$ses->getIP) >= $c->{max_money_last24};
         #$ses->AdminLog("SmartProfit: IP=".$ses->getIP." Country=$country Money=$money");
      }
      else
      {
         $money = $ses->getUser && $ses->getUser->{premium} ? $c->{dl_money_prem} : $c->{dl_money_reg};
         $money = $c->{dl_money_anon} unless $ses->getUser;
         refuse('REWARD_NOT_SPECIFIED') if !$money;
         refuse('FILE_TOO_SMALL') if $file->{file_size} < $c->{money_filesize_limit}*1024*1024;
      }
      $money = $money / 1000;
      refuse("OWN_FILE") if $usr_id && $file->{usr_id}==$usr_id && $c->{no_money_from_uploader_user};
      refuse("OWN_IP") if $file->{file_ip} eq $ses->getIP && $c->{no_money_from_uploader_ip};

      my $owner = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $file->{usr_id}) if $file->{usr_id};
      if($owner && $ses->iPlg('p'))
      {
         $file->{usr_profit_mode} = lc $file->{usr_profit_mode};
         my $perc = $c->{"m_y_$file->{usr_profit_mode}_dl"};
         refuse("NO_PERCENT_SPECIFIED") if !$perc;

         if($c->{m_y_manual_approve} && !$owner->{usr_aff_enabled})
         {
            refuse("NOT_APPROVED_AFFILIATE");
            $perc = 0;
         }

         $money = $money*$perc/100;
         refuse("NOT_PPD") if !$money && $file->{usr_profit_mode} ne 'ppd';
      }

      $money = sprintf("%.05f",$money);

      if($money>0 && $f->{referer})
      {
         my $ref_url = $f->{referer};
         $ref_url=~s/^https?:\/\///i;
         $ref_url=~s/^www\.//i;
         $ref_url=~s/\/.+$//;
         $ref_url=~s/[\/\s]+//g;
         my $usr_id2 = $db->SelectOne("SELECT usr_id FROM Websites WHERE domain=?",$ref_url);
         if($usr_id2)
         {
            my $money2 = sprintf("%.05f", $money*$c->{m_x_rate}/100 );

            $db->Exec("UPDATE Users 
                       SET usr_money=usr_money+? 
                       WHERE usr_id=?", $money2, $usr_id2);

            $db->Exec("INSERT INTO Stats2
                       SET usr_id=?, day=CURDATE(),
                           profit_site=?
                       ON DUPLICATE KEY UPDATE
                           profit_site=profit_site+?
                      ",$usr_id2,$money2,$money2);
            $total_money_charged += $money2;
         }
      }

      $db->Exec("INSERT IGNORE INTO IP2Files 
                 SET file_id=?, 
                     usr_id=?, 
                     owner_id=?, 
                     ip=INET_ATON(?), 
                     size=?, 
                     money=?,
                     referer=?,
                     status=?",$file->{file_id},$usr_id,$file->{usr_id}||0,$ses->getIP,$file->{file_size},$money,$f->{referer}||'',$status);

      $db->Exec("UPDATE LOW_PRIORITY Files 
                 SET file_downloads=file_downloads+1, 
                     file_money=file_money+?, 
                     file_last_download=NOW() 
                 WHERE file_id=?",$money,$file->{file_id});

      $db->Exec("UPDATE LOW_PRIORITY Users SET usr_money=usr_money+? WHERE usr_id=?",$money,$file->{usr_id}) if $file->{usr_id} && $money;

      $total_money_charged += $money if $file->{usr_id};

      $db->Exec("INSERT INTO Stats2
                 SET usr_id=?, day=CURDATE(),
                     downloads=1, profit_dl=$money
                 ON DUPLICATE KEY UPDATE
                     downloads=downloads+1, profit_dl=profit_dl+$money
                ",$file->{usr_id}) if $file->{usr_id};

      if($file->{usr_id} && $c->{referral_aff_percent} && $money)
      {
         my $aff_id = $db->SelectOne("SELECT usr_aff_id FROM Users WHERE usr_id=?",$file->{usr_id});
         my $money_ref = sprintf("%.05f",$money*$c->{referral_aff_percent}/100);
         if($aff_id && $money_ref>0)
         {
            $total_money_charged += $money_ref;
            $db->Exec("UPDATE Users SET usr_money=usr_money+? WHERE usr_id=?", $money_ref, $aff_id);
            $db->Exec("INSERT INTO Stats2
                  SET usr_id=?, day=CURDATE(),
                  profit_refs=$money_ref
                  ON DUPLICATE KEY UPDATE
                  profit_refs=profit_refs+$money_ref
                  ",$aff_id);
         }
      }
      $db->Exec("INSERT INTO Stats SET day=CURDATE(), downloads=1,bandwidth=$file->{file_size},paid_to_users='$total_money_charged' ON DUPLICATE KEY UPDATE downloads=downloads+1,bandwidth=bandwidth+$file->{file_size},paid_to_users=paid_to_users+'$total_money_charged'");
   }
}

sub CommentsList
{
   my ($cmt_type,$cmt_ext_id) = @_;
   my $list = $db->SelectARef("SELECT *, INET_NTOA(cmt_ip) as ip, DATE_FORMAT(created,'%M %e, %Y') as date, DATE_FORMAT(created,'%r') as time
                               FROM Comments 
                               WHERE cmt_type=? 
                               AND cmt_ext_id=?
                               ORDER BY created",$cmt_type,$cmt_ext_id);
   for (@$list)
   {
      $_->{cmt_text}=~s/\n/<br>/gs;
      $_->{cmt_name} = "<a href='$_->{cmt_website}'>$_->{cmt_name}</a>" if $_->{cmt_website};
      if($ses->getUser && $ses->getUser->{usr_adm})
      {
         $_->{email} = $_->{cmt_email};
         $_->{adm} = 1;
      }
   }
   return $list;
}

sub DeURL
{
   return $ses->message("Not allowed") if !$c->{m_j};
   $ses->{form}->{no_hdr}=1;
   return $ses->PrintTemplate("deurl.html", msg => "Invalid link ID") unless $f->{id}=~/^\w+$/;
   require Math::Base62;
   my $file_id = $f->{mode} == 2 ? Math::Base62::decode_base62($f->{id}) : $ses->decode32($f->{id});
   my $file = $db->SelectRow("SELECT * FROM Files WHERE file_id=?",$file_id);
   return $ses->PrintTemplate("download1_no_file.html") unless $file;
   $ses->PrintTemplate("deurl.html", msg => "File was deleted") unless $file;
   $ses->PrintTemplate("deurl.html", 
                       referer => $ENV{HTTP_REFERER}||'',
                       %$file,
                       %{$c},
                      );
}

sub getTime
{
    my ($t) = @_;
    my @t = $t ? localtime($t) : localtime();
    return ( sprintf("%04d",$t[5]+1900),
             sprintf("%02d",$t[4]+1), 
             sprintf("%02d",$t[3]), 
             sprintf("%02d",$t[2]), 
             sprintf("%02d",$t[1]), 
             sprintf("%02d",$t[0]) 
           );
}

1;
