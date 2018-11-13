package XUtils;
use strict;
use XFileConfig;
use JSON;

sub ReportFile
{
   # Adds the file in abuses list
   # %opts: usr_id - reporter's ID
   #        ban - ban file by (file_md5, file_size)
   my ($ses, $file, %opts) = @_;
   my $db = $ses->db;
   my $reporter = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $opts{usr_id}) if $opts{usr_id};
   $reporter ||= { usr_id => 0, usr_login => $opts{usr_login}, usr_email => $opts{usr_email} } if $opts{usr_login};
   my $ban = ",ban_size='$file->{file_size}', ban_md5='$file->{file_md5}' " if $ses->getUser->{takedown_md5};
   $db->Exec("INSERT INTO Reports SET file_id=?,
         usr_id=?,
         filename=?,
         name=?,
         email=?,
         info='auto',
         created=NOW() $ban",
         $file->{file_id},
         $file->{usr_id},
         $file->{file_name},
         $reporter->{usr_login},
         $reporter->{usr_email},
         );
}

sub RunServerTests
{
   my ($ses, $srv_id) = @_;
   my $db = $ses->db;
   my $server = $db->SelectRow("SELECT * FROM Servers WHERE srv_id=?", $srv_id);

   require LWP::UserAgent;
   my $ua = LWP::UserAgent->new( timeout => 15, agent => 'Opera/9.51 (Windows NT 5.1; U; en)' );

   my @tests;
   # api.cgi multiple tests
   my $res = $ses->api2( $srv_id, { op => 'test', site_cgi => $c->{site_cgi} } );
   if ( $res =~ /^OK/ )
   {
      push @tests, 'api.cgi: OK';
      $res =~ s/^OK:(.*?)://;
      push @tests, split( /\|/, $res );
   }
   else
   {
      push @tests, "api.cgi: ERROR ($res)";
   }

   # upload.cgi
   $res = $ua->get("$server->{srv_cgi_url}/upload.cgi?mode=test");
   push @tests, $res->content eq 'XFS' ? 'upload.cgi: OK' : "upload.cgi: ERROR (problems with <a href='$server->{srv_cgi_url}/upload.cgi\?mode=test' target=_blank>link</a>)";

   # htdocs URL accessibility
   $res = $ua->get("$server->{srv_htdocs_url}/index.html");
   push @tests, $res->content eq 'XFS' ? 'htdocs URL accessibility: OK' : "htdocs URL accessibility: ERROR (should see XFS on <a href='$server->{srv_htdocs_url}/index.html' target=_blank>link</a>)";
   return(@tests);

}

sub Ban
{
   # Purpose: ban user and/or IP
   my ($ses, %opts) = @_;
   if($opts{usr_id})
   {
      # Also ban user in XFileSharing <= 2.0 way
      $ses->db->Exec("UPDATE Users SET usr_status='BANNED' WHERE usr_id=?", $opts{usr_id});
   }
   $ses->db->Exec("INSERT IGNORE INTO Bans SET usr_id=?,
               ip=INET_ATON(?),
               reason=?",
         $opts{usr_id}||0,
         $opts{ip}||0,
         $opts{reason}||'',
         );
}

sub CreateTransaction
{
   # Purpose: create a new payment transaction
   # Returns: new transaction id
   my ($ses, %opts) = @_;
   my $db = $ses->db;
   my $id = int( 1 + rand 9 ) . join( '', map { int( rand 10 ) } 1 .. 9 );
   $db->Exec("INSERT INTO Transactions SET id=?, usr_id=?, amount=?, ip=INET_ATON(?), created=NOW(), aff_id=?, ref_url=?, verified=?, origin=?",
         $id,
         $opts{usr_id},
         $opts{amount},
         $ses->getIP||'0.0.0.0',
         $opts{aff_id}||0,
         $opts{ref_url}||'',
         $opts{verified}||0,
         $opts{origin}||'',
         );
   return($id);
}

sub chargeRef
{
   # Purpose: add $amount to $usr_id and run the necessary hooks
   # Returns: amount charged
   my ($ses, $usr_id, $amount, %opts) = @_;
   my $db = $ses->db;
   $opts{type} ||= 'seller';
   die("Unknown referral type: $opts{type}")
      if $opts{type} !~ /^(seller|referral|webmaster)/;

   $ses->AdminLog("Charging $amount to $opts{type} $usr_id");
   $db->Exec("UPDATE Users SET usr_money=usr_money+? WHERE usr_id=?", $amount, $usr_id) if $usr_id && $amount;

   # Updating stats
   my $f_count = {   seller => 'sales',
      }->{$opts{type}};
   my $f_amount = {   seller => 'profit_sales',
         referral => 'profit_refs',
         webmaster => 'profit_site',
      }->{$opts{type}};
   if($f_count)
   {
      $db->Exec("INSERT INTO Stats2
                      SET usr_id=?, day=CURDATE(), $f_count=1
            ON DUPLICATE KEY UPDATE $f_count=$f_count+1", $usr_id);
   }
   $db->Exec("INSERT INTO Stats2
                      SET usr_id=?, day=CURDATE(), $f_amount=$amount
                      ON DUPLICATE KEY UPDATE $f_amount=$f_amount+$amount",$usr_id) if $c->{m_s} && $usr_id;
   return($amount);
}

sub TestFile
{
   my ($db, $file_code) = @_;
   my $file = $db->SelectRow("SELECT *, INET_NTOA(file_ip) as file_ip, u.usr_profit_mode, s.srv_htdocs_url
                              FROM (Files f, Servers s)
                              LEFT JOIN Users u ON f.usr_id = u.usr_id 
                              WHERE f.file_code=? 
                              AND f.srv_id=s.srv_id",$file_code);
   return undef if !$file;
   my $direct_link = &genDirectLink($file, ip => '1.1.1.1');
   require LWP::UserAgent;
   my $ua = LWP::UserAgent->new( timeout => 1, agent => 'Opera/9.51 (Windows NT 5.1; U; en)' );
   my $res = $ua->head($direct_link);
   return $res->code;
}

sub CheckAuth
{
  my ($ses, $sess_id) = @_;
  my $sess_id = $ses->getCookie( $ses->{auth_cook} );
  my $db= $ses->db;
  my $f= $ses->f;
  return undef unless $sess_id;
  $ses->{user} = $db->SelectRow("SELECT u.*,
                                        UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec,
                                        UNIX_TIMESTAMP()-UNIX_TIMESTAMP(last_time) as dtt,
                                        s.last_ip
                                 FROM Users u, Sessions s 
                                 WHERE s.session_id=? 
                                 AND s.usr_id=u.usr_id",$sess_id);
  unless($ses->{user})
  {
     return undef;
  }
  if ( $ses->{user}->{usr_adm} && ( my $view_as = $ses->getCookie('view_as_usr_id') ) )
  {
     $ses->{user} = $db->SelectRow(
           "SELECT *,
           UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec
           FROM Users
           WHERE usr_id=?", $view_as);

     $ses->{lang}->{fake_user} = 1;
  }
  else
  {
     $ses->{lang}->{fake_user} = 0;
  }
  if($ses->{user}->{usr_status} eq 'BANNED')
  {
     delete $ses->{user};
     $ses->{msg} = "Your account was banned by administrator.";
     return undef;
  }
  if($c->{mod_sec_restrict_session_ip} && $ses->{user}->{last_ip} ne $ses->getIP)
  {
     delete $ses->{user};
     return undef;
  }
  if($ses->{user}->{dtt}>30)
  {
     $db->Exec("UPDATE Sessions SET last_ip=?, last_useragent=?, last_time=NOW() WHERE session_id=?",
        $ses->getIP, $ses->getEnv('HTTP_USER_AGENT')||'', $sess_id);
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

  $ses->{lang}->{enable_reports} = $c->{enable_reports};

  #$ses->setCookie( $ses->{auth_cook} , $sess_id );
  return $ses->{user};
}

sub CheckLoginPass
{
   use MIME::Base64;
   use PBKDF2::Tiny;

   my ($ses, $login, $pass) = @_;

   my $user = $ses->db->SelectRow("SELECT * FROM Users WHERE usr_login=?  AND !usr_social", $login);

   my $answer = $user->{usr_password} =~ /^sha256:/
      ? _check_password_pbkdf2($pass, $user->{usr_password})
      : _check_password_legacy($pass, $ses->db, $user->{usr_id});

   return GetUser($ses, $user->{usr_id}) if $answer;
   return 0;
}

sub _check_password_pbkdf2
{
   my ($actual_pass, $hashed_pass) = @_;
   my ($algo, $turns, $salt, $data) = split(/:/, $hashed_pass);
   return PBKDF2::Tiny::verify( decode_base64($data), 'SHA-256', $actual_pass, decode_base64($salt), $turns );
}

sub _check_password_legacy
{
   my ($actual_pass, $db, $usr_id) = @_;
   return $db->SelectOne("SELECT usr_id FROM Users
      WHERE usr_id=?
      AND usr_password=ENCODE(?, ?)",
      $usr_id,
      $actual_pass,
      $c->{pasword_salt});
}

sub GetUser
{
   my ($ses, $usr_id) = @_;
   my $user = $ses->db->SelectRow("SELECT *, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec 
         FROM Users 
         WHERE usr_id=?", $usr_id );
   if($user && $user->{usr_status} eq 'BANNED')
   {
      delete $ses->{user};
      $ses->{msg} = "Your account was banned by administrator.";
      return undef;
   }

   $user->{utype} = $user ? ($user->{exp_sec} > 0 ? 'prem' : 'reg') : 'anon' if $user;

   return $user;
}

sub SelectServer
{
   my $ses = shift;
   my $user = shift;

   my @custom_filters = map { " AND $_"} @_;
   my $type_filter = $user && $user->{exp_sec} > 0 ? "AND srv_allow_premium=1" : "AND srv_allow_regular=1";
   my $country_filter;

   if($c->{m_g} && -f "$c->{cgi_path}/GeoIP.dat")
   {
      require Geo::IP;
      my $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
      my $country = $gi->country_code_by_addr($ses->getIP);
      $country_filter="AND srv_countries LIKE '%$country%'" if $country;
      $country_filter||="AND srv_countries=''";
   }

   my $server = $ses->db->SelectRow("SELECT * FROM Servers 
                                WHERE srv_status='ON' 
                                AND srv_disk+? <= srv_disk_max*0.99
                                $type_filter
                                $country_filter
                                @custom_filters
                                ORDER BY RAND()
                                LIMIT 1",$c->{max_upload_filesize}||100);
   if($c->{m_g} && !$server)
   {
      $server = $ses->db->SelectRow("SELECT * FROM Servers 
                                WHERE srv_status='ON' 
                                AND srv_disk+? <= srv_disk_max*0.98
                                $type_filter
                                @custom_filters
                                ORDER BY RAND()
                                LIMIT 1",$c->{max_upload_filesize}||100);
   }

   return $server;
}

sub GenPasswdHash
{
   require PBKDF2::Tiny;
   require MIME::Base64;

   my ($pass) = @_;
   my $turns = 1000;
   my $salt = join('', map { chr( rand(256) ) } (1..24));
   my $data = PBKDF2::Tiny::derive('SHA-256', $pass, $salt, $turns);
   my $hash = sprintf("sha256:%d:%s:%s",
      $turns,
      MIME::Base64::encode_base64($salt, ''),
      MIME::Base64::encode_base64($data, ''));

   return $hash;
}

sub TrackDL
{
   my ($ses, $file, %opts) = @_;
   my $db = $ses->db;

   my $total_money_charged = 0;
   my $usr_id = $opts{usr_id};

   my ($money, $status);

   local *refuse = sub
   {
      $status ||= shift;
      $money = 0;
   };

   if($ses->iPlg('p') && -e "$c->{cgi_path}/GeoIP.dat")
   {
      my $size_id;
      my @ss = split(/\|/,$c->{tier_sizes});
      for(0..5){$size_id=$_ if defined $ss[$_] && $file->{file_size}>=$ss[$_]*1024*1024;}
      require Geo::IP;
      my $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
      my $country = $gi->country_code_by_addr($opts{ip});
      if(defined $size_id)
      {
        my $tier_money = $c->{tier4_money};
        if   ($c->{tier1_countries} && $country=~/^($c->{tier1_countries})$/i){ $tier_money = $c->{tier1_money}; }
        elsif($c->{tier2_countries} && $country=~/^($c->{tier2_countries})$/i){ $tier_money = $c->{tier2_money}; }
        elsif($c->{tier3_countries} && $country=~/^($c->{tier3_countries})$/i){ $tier_money = $c->{tier3_money}; }
        $money = (split(/\|/,$tier_money))[$size_id];
        refuse('REWARD_NOT_SPECIFIED') if !$money;
      }

      refuse('MAX24_REACHED') if $c->{max_money_last24} && $db->SelectOne("SELECT SUM(money) FROM IP2Files WHERE ip=INET_ATON(?) AND created>NOW()-INTERVAL 24 HOUR",$opts{ip}) >= $c->{max_money_last24};
      refuse('MAX24_REACHED') if $c->{max_paid_dls_last24} && $db->SelectOne("SELECT COUNT(*) FROM IP2Files WHERE ip=INET_ATON(?) AND created>NOW()-INTERVAL 24 HOUR AND money > 0",$opts{ip}) >= $c->{max_paid_dls_last24};
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
   refuse("OWN_IP") if $file->{file_ip} eq $opts{ip} && $c->{no_money_from_uploader_ip};
   refuse('ADBLOCK') if $opts{adblock_detected};
   refuse('GEOIP_MISSING') if $ses->iPlg('p') && ! -e "$c->{cgi_path}/GeoIP.dat";

   my $owner = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $file->{usr_id}) if $file->{usr_id};
   if($owner && $ses->iPlg('p'))
   {
      my $profit_mode = lc($owner->{usr_profit_mode});
      my $perc = $c->{"m_y_$profit_mode\_dl"};
      refuse('NO_MIXED_PERCENT') if !$perc && $profit_mode eq 'mix';
      refuse('NOT_PPD') if !$perc && $profit_mode ne 'ppd';
      refuse("NO_PERCENT_SPECIFIED: ".$profit_mode) if !$perc;

      if($c->{m_y_manual_approve} && !$owner->{usr_aff_enabled})
      {
         refuse("NOT_APPROVED_AFFILIATE");
         $perc = 0;
      }

      $money = $money*$perc/100;
      refuse("NOT_PPD") if !$money && $profit_mode ne 'ppd';
   }

   $money = sprintf("%.05f",$money);

   if($money>0 && $opts{referer})
   {
      my $ref_url = $opts{referer};
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

   $status ||= 'Completed';

   $db->Exec("INSERT INTO IP2Files 
              SET file_id=?, 
                  usr_id=?, 
                  owner_id=?, 
                  ip=INET_ATON(?), 
                  size=?, 
                  money=?,
                  referer=?,
                  status=?,
                  finished=1
               ON DUPLICATE KEY UPDATE
                  money=?,
                  status=?,
                  finished=1",
               $file->{file_id},
               $usr_id,
               $file->{usr_id}||0,
               $opts{ip},
               $file->{file_size},
               $money,
               $opts{referer}||'',
               $status,
               $money,
               $status);

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

sub AddToReports
{
   my ($ses, $file) = @_;
   my $db = $ses->db;

   $db->Exec("INSERT INTO Reports SET file_id=?, usr_id=?, filename=?, name=?, email=?, reason=?, info=?, ip=INET_ATON(?), status='PENDING', created=NOW()",
      $file->{file_id},
      $ses->getUserId,
      $file->{file_name},
      $ses->getUser->{usr_login},
      $ses->getUser->{usr_email},
      'Mass DMCA',
      '',
      $ses->getIP);
}

sub getTorrents
{
   my $ses = $Engine::Core::ses;
   my $db = $Engine::Core::db;

   my (%opts) = @_;
   my $filter_usr_id = "AND t.usr_id=" . int($opts{usr_id}) if $opts{usr_id};
   my $torrents=[];
   if($ses->iPlg('t'))
   {
      $torrents = $db->SelectARef("SELECT *, u.usr_login, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(created) as working
                                   FROM Torrents t
                                   LEFT JOIN Users u ON u.usr_id=t.usr_id
                                   WHERE status='WORKING' 
                                   $filter_usr_id
                                   ");
      for my $t (@$torrents)
      {
         my $files = eval { JSON::decode_json($t->{files}) } if $t->{files};
         $t->{file_list} = join('<br>',map{$ses->SecureStr($_->{path}) . " (<i>".sprintf("%.1f Mb",$_->{size}/1048576)."<\/i>)"} @$files );
         $t->{title} = $ses->SecureStr($t->{name});
         $t->{title}=~s/\/.+$//;
         $t->{title}=~s/:\d+$//;
         ($t->{done},$t->{total},$t->{down_speed},$t->{up_speed})=split(':',$t->{progress});
         $t->{percent} = sprintf("%.01f", 100*$t->{done}/$t->{total} ) if $t->{total};
         $t->{done} = sprintf("%.1f", $t->{done}/1048576 );
         $t->{total} = sprintf("%.1f", $t->{total}/1048576 );
         $t->{working} = $t->{working}>3600*3 ? sprintf("%.1f hours",$t->{working}/3600) : sprintf("%.0f mins",$t->{working}/60);
         $t->{down_speed} = $ses->makeFileSize($t->{down_speed});
         $t->{up_speed} = $ses->makeFileSize($t->{up_speed});
      }
   }

   return $torrents;
}

sub buildTree
{
   my ($fh,$parent,$depth)=@_;
   my @tree;
   for my $x (@{$fh->{$parent}})
   {
      $x->{pre}='&nbsp;&nbsp;'x$depth;
      push @tree, $x;
      push @tree, &buildTree($fh,$x->{fld_id},$depth+1);
   }
   return @tree;
}

sub buildFoldersTree
{
   my (%opts) = @_;
   my $allfld = $Engine::Core::ses->db->SelectARef("SELECT * FROM Folders WHERE usr_id=? AND !fld_trashed ORDER BY fld_name",$opts{usr_id});
   my $fh;
   push @{$fh->{$_->{fld_parent_id}}},$_ for @$allfld;
   return( &buildTree($fh,0,0) );
}

sub getPluginsOptions
{
   my ($plgsection, $data) = @_;
   my @ret;
   for($Engine::Core::ses->getPlugins($_[0]))
   {
      my $hashref = eval("\$$_\::options") || $_->options;
      my $aref = [];

      # Regular plugins
      $aref = $hashref->{s_fields} if $hashref->{s_fields};

      # Compatibility with XFM Leech plugins
      $aref = [ { name => "$hashref->{plugin_prefix}\_logins", domain => ucfirst($hashref->{domain}) } ] if $hashref->{plugin_prefix};

      $_->{value} = $data ? $data->{$_->{name}} : $c->{$_->{name}} for @$aref;
      $_->{"type_$_->{type}"} = 1 for @$aref;

      push @ret, @$aref;
   }
   return \@ret;
}

sub formatAmount
{
   my $arg = shift;
   $arg=~s/(\.[^0]*)0+$/$1/;
   $arg=~s/\.$//;
   return $arg;
}

sub computeMonthlyPrice
{
   my @sorted = sort { abs($a->{day}-30) <=> abs($b->{day}-30) } @_;
   return sprintf("%d", 30 * $sorted[0]->{amount} / $sorted[0]->{days}) if @sorted;
}

sub getAffiliate
{
   my $usr_id = $Engine::Core::ses->getUser ? $Engine::Core::ses->getUserId : 0;

   my $aff_id;
   $aff_id = $Engine::Core::ses->getCookie('aff')||0;
   $aff_id = 0 if $aff_id==$usr_id;
   $aff_id = $Engine::Core::ses->getUser->{usr_aff_id} if $Engine::Core::ses->getUser && $Engine::Core::ses->getUser->{usr_aff_id} && !$aff_id;
   return($aff_id||0);
}

sub StartSession
{
   my ($usr_id) = @_;
   my $sess_id = $Engine::Core::ses->randchar(16);
   $Engine::Core::db->Exec("DELETE FROM Sessions WHERE last_time + INTERVAL 5 DAY < NOW()");
   $Engine::Core::db->Exec("INSERT INTO Sessions (session_id,usr_id,last_ip,last_useragent,last_time) VALUES (?,?,?,?,NOW())",
      $sess_id,$usr_id,$Engine::Core::ses->getIP,$Engine::Core::ses->getEnv('HTTP_USER_AGENT')||'');
   $Engine::Core::db->Exec("UPDATE Users SET usr_lastlogin=NOW(), usr_lastip=INET_ATON(?) WHERE usr_id=?", $Engine::Core::ses->getIP, $usr_id );
   return $sess_id;
}

sub GetSession
{
   my ($usr_id) = @_;
   my $session = $Engine::Core::db->SelectRow("SELECT * FROM Sessions WHERE usr_id=?", $usr_id);
   return $session ? $session->{session_id} : &StartSession($usr_id);
}

sub makeSortSQLcode
{
  my ($f,$default_field) = @_;
  
  my $sort_field = $f->{sort_field} || $default_field;
  my $sort_order = $f->{sort_order} eq 'down' ? 'DESC' : '';
  $sort_field=~s/[^\w\_]+//g;

  return " ORDER BY $sort_field $sort_order ";
}

sub makeSortHash
{
   my ($f,$fields) = @_;
   my @par;
   foreach my $key (keys %{$f})
   {
    next if $key=~/^(sort_field|sort_order|load)$/i;
    my $val = $f->{$key};
    $key =~ s/['"]//g;
    $val =~ s/['"]//g;
    push @par, (ref($val) eq 'ARRAY' ? map({"$key=$_"}@$val) : "$key=$val");
   }
   my $params = join('&amp;',@par);
   my $sort_field = $f->{sort_field};
   my $sort_order = $f->{sort_order} || 'down';
   $sort_field ||= $fields->[0];
   my $sort_order2 = $sort_order eq 'down' ? 'up' : 'down';   
   my %hash = ('sort_'.$sort_field         => 1,
               'sort_order_'.$sort_order2  => 1,
               'params'                    => $params,
              );
   for my $fld (@$fields)
   {
      if($fld eq $sort_field)
      {
         $hash{"s_$fld"}  = "<a href='?$params&amp;sort_field=$fld&amp;sort_order=$sort_order2'>";
         $hash{"s2_$fld"} = "<img border=0 src='$c->{site_url}/images/$sort_order.gif'>"
      }
      else
      {
         $hash{"s_$fld"}  = "<a href='?$params&amp;sort_field=$fld&amp;sort_order=down'>";
      }
      $hash{"s2_$fld"}.= "</a>";
   }

   return %hash;
}

sub genChart
{
   use List::Util qw(max);
   my ($list, $field, %opts) = @_;

   my @ret;
   push @ret, [ 'Date', $field ];
   push @ret, map { [ $_->{x}, int($_->{$field}) ] } @$list;

   return \@ret;
}

sub DownloadChecks
{
   my ($file) = @_;

   my $owner = $Engine::Core::db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $file->{usr_id});
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
      my $cond = $Engine::Core::ses->getUser ? "usr_id=".$Engine::Core::ses->getUserId : "ip=INET_ATON('".$Engine::Core::ses->getIP."')";
      my $last = $Engine::Core::db->SelectRow("SELECT *, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(created) as dt 
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
      my $cond = $Engine::Core::ses->getUser ? "usr_id=".$Engine::Core::ses->getUserId : "ip=INET_ATON('".$Engine::Core::ses->getIP."')";
      my $last = $Engine::Core::db->SelectRow("SELECT *, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(created) as dt 
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

   if($Engine::Core::ses->getUserLimit('bw_limit'))
   {
      $file->{message} = "You have reached the download-limit: $c->{bw_limit} Mb for last $c->{bw_limit_days} days"
         if $Engine::Core::ses->getUserBandwidth($c->{bw_limit_days}) > $Engine::Core::ses->getUserLimit('bw_limit');
   }

   if($file->{file_premium_only} && $Engine::Core::ses->{utype} ne 'prem')
   {
      $Engine::Core::ses->PrintTemplate("download_premium_only.html",%$file), return;
   }

   return $file;
}

sub getMaxDLSize
{
   my ($owner) = @_;
   my $usr_aff_max_dl_size = $owner->{usr_aff_max_dl_size} if $owner && $owner->{usr_aff_enabled} && $Engine::Core::ses->{utype} ne 'prem';
   return $usr_aff_max_dl_size || $c->{max_download_filesize};
}

sub CommentsList
{
   my ($cmt_type,$cmt_ext_id) = @_;
   my $list = $Engine::Core::db->SelectARef("SELECT *, INET_NTOA(cmt_ip) as ip, DATE_FORMAT(created,'%M %e, %Y') as date, DATE_FORMAT(created,'%r') as time
                               FROM Comments 
                               WHERE cmt_type=? 
                               AND cmt_ext_id=?
                               ORDER BY created",$cmt_type,$cmt_ext_id);
   for (@$list)
   {
      $_->{cmt_text}=~s/\n/<br>/gs;
      $_->{cmt_name} = "<a href='$_->{cmt_website}'>$_->{cmt_name}</a>" if $_->{cmt_website};
      if($Engine::Core::ses->getUser && $Engine::Core::ses->getUser->{usr_adm})
      {
         $_->{email} = $_->{cmt_email};
         $_->{adm} = 1;
      }
   }
   return $list;
}

sub DownloadTrack
{
   my ($file) = @_;
   my $usr_id = $Engine::Core::ses->getUser ? $Engine::Core::ses->getUserId : 0;
   my $f = $Engine::Core::ses->f;

   my $total_money_charged = 0;
   
   if(!$Engine::Core::db->SelectOne("SELECT file_id FROM IP2Files WHERE file_id=? AND ip=INET_ATON(?) AND usr_id=?",$file->{file_id},$Engine::Core::ses->getIP,$usr_id))
   {
      $f->{referer}||= $Engine::Core::ses->getCookie('ref_url') || $Engine::Core::ses->getEnv('HTTP_REFERER');
      $f->{referer}=~s/$c->{site_url}//i;
      $f->{referer}=~s/^http:\/\///i;

      if($c->{m_n_100_complete_percent})
      {
         # Don't charge any money, leave it for fs.cgi instead
         $Engine::Core::db->Exec("INSERT INTO IP2Files SET 
               file_id=?, usr_id=?, owner_id=?, ip=INET_ATON(?), size=0, referer=?, status=?",      
               $file->{file_id},$usr_id||0,$file->{usr_id}||0,$Engine::Core::ses->getIP,$f->{referer}||'',
               ($f->{adblock_detected} ? 'ADBLOCK' : 'Not completed'));
         return;
      }

      XUtils::TrackDL($Engine::Core::ses, $file,
         adblock_detected => $f->{adblock_detected}||'',
         referer => $f->{referer},
         ip => $Engine::Core::ses->getIP,
         usr_id => $Engine::Core::ses->getUser ? $Engine::Core::ses->getUserId : 0);
   }
}

sub VideoMakeCode
{
   my ($file,$gen) = @_;
   my ($ext) = $file->{file_name}=~/\.(\w+)$/i;
   my $f = $Engine::Core::ses->f;

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
   my $direct_link = $Engine::Core::ses->getPlugins('CDN')->genDirectLink($file,
      encoded => 1,
      file_name => "video.$ext",
      accept_ranges => 1,
      limit_conn => max( $c->{m_n_limit_conn}, 10 ));
   return if !$direct_link;
   $file->{video_code} = $Engine::Core::ses->getPlugins('Video')->makeCode($file, $direct_link);

   # Ads overlay mod
   if($c->{m_a} && $file->{video_code})
   {
      $file->{m_a_css}="document.write('<Style>#player_img {position:absolute;}
a#vid_play {background: repeat scroll center top; display:block; position:absolute; top:50%; margin-top:-30px; left:15%; margin-left:-30px; z-index: 99; width: 60px; height: 60px;}
a#vid_play:hover {background-position:bottom;}
#player_ads {position:absolute; top:0px; left:30%; width:70%; height:100%; z-index:2;}
#player_code {visibility: hidden;}</Style>');";
      $file->{m_a_css} = $Engine::Core::ses->encodeJS($file->{m_a_css});
   }

   return $file;
}

sub ARef
{
  my $data=shift;
  $data=[] unless $data;
  $data=[$data] unless ref($data) eq 'ARRAY';
  return $data;
}

sub UserFilters
{
   my ($f) = @_;

   my @filters = ();
   push @filters, "AND usr_lastlogin > NOW() - INTERVAL $f->{filter_lastlogin} DAY" if $f->{filter_lastlogin};
   push @filters, "AND usr_premium_expire>NOW()" if $f->{status} eq 'premium';
   push @filters, "AND usr_premium_expire <= NOW()" if $f->{status} eq 'free';
   push @filters, "AND usr_reseller" if $f->{status} eq 'reseller';
   push @filters, "AND usr_dmca_agent" if $f->{status} eq 'dmca_agent';
   push @filters, "AND usr_aff_enabled" if $f->{status} eq 'aff_enabled';
   push @filters, "AND usr_mod" if $f->{status} eq 'mod';
   push @filters, "AND usr_adm" if $f->{status} eq 'adm';
   push @filters, "AND usr_status='PENDING'" if $f->{status} eq 'pending';
   push @filters, "AND usr_status='BANNED'" if $f->{status} eq 'banned';
   push @filters, "AND usr_money>=$f->{money}" if $f->{money} =~ /^[\d\.]+$/;

   if($f->{key})
   {
      push @filters, ($f->{key} =~ /^\d+\.\d+\.\d+\.\d+$/
         ? "AND usr_lastip=INET_ATON('$f->{key}')"
         : "AND (usr_login LIKE '%$f->{key}%' OR usr_email LIKE '%$f->{key}%')");
   }

   return wantarray() ? @filters : join(" ", @filters);
}

sub MapFileServers
{
   my ($ses, $args, $legend) = @_;

   my $servers = $ses->{db}->SelectARef("SELECT * FROM Servers WHERE srv_status<>'OFF'");

   for my $srv (@$servers)
   {
      print "$legend for SRV=$srv->{srv_id}..." if $legend;
      my $res = $ses->api(
         $srv->{srv_cgi_url},
         {
            fs_key => $srv->{srv_key},
            %$args,
         }
      );
      if ( $res =~ /OK/ )
      {
         print "Done.<br>\n";
      }
      else
      {
         print "Error when deleting syms. SRV=$srv->{srv_id}.<br>\n$res<br><br>";
         $ses->AdminLog("Error when deleting syms. ServerID: $srv->{srv_id}.\n$res");
      }
   }
}

sub SMSConfirm
{
   my $ses = $Engine::Core::ses;
   my $db = $Engine::Core::db;
   my $f = $ses->f;
   my ($purpose, $msg) = @_;

   $db->Exec("DELETE FROM SecurityTokens WHERE created < NOW() - INTERVAL 30 MINUTE AND purpose=?", $purpose);

   if($f->{confirm})
   {
      delete $f->{confirm};
      my $token = $Engine::Core::db->SelectRow("SELECT * FROM SecurityTokens WHERE usr_id=? AND ip=INET_ATON(?) AND purpose=? AND value=? AND created > NOW() - INTERVAL 30 MINUTE",
         $ses->getUserId, $ses->getIP, $purpose, $f->{code});
      $db->Exec("DELETE FROM SecurityTokens WHERE usr_id=? AND purpose=?", $token->{usr_id}, $token->{purpose}) if $token;
      return $token && $token->{id} ? 1 : SMSConfirm($purpose, "Invalid code");
   }
   else
   {
      my $user = $ses->getUser;
      my $token = $Engine::Core::db->SelectRow("SELECT * FROM SecurityTokens WHERE usr_id=? AND ip=INET_ATON(?) AND purpose=? AND created > NOW() - INTERVAL 1 MINUTE",
         $ses->getUserId, $ses->getIP, $purpose);

      if(!$token)
      {
         my $secret_code = $ses->randchar(8);

         $db->Exec("INSERT INTO SecurityTokens SET usr_id=?, purpose=?, ip=INET_ATON(?), value=?, phone=?",
            $ses->getUserId, $purpose, $ses->getIP, $secret_code, $user->{usr_phone});

         return $ses->message("Error while sending SMS: $ses->{errstr}")
            if !$ses->SendSMS( $user->{usr_phone}, "$c->{site_name} login confirmation code: $secret_code" );
      }
   
      my @fields = map { { name => $_, value => $f->{$_} } } grep { !/^(confirm|token|code)$/ } keys(%$f);

      delete($ses->{user});
      $f->{msg} ||= $msg;

      $ses->PrintTemplate("sms_check.html",
         phone => $user->{usr_phone},
         usr_id => $user->{usr_id},
         purpose => $purpose,
         interval => $c->{countdown_before_next_sms}||60,
         fields => \@fields);
      return undef;
   }
}

sub CloneFile
{
   my ($ses, $file,%opts) = @_;
   my $db = $ses->db;

   my $code = $ses->randchar(12);
   while($db->SelectOne("SELECT file_id FROM Files WHERE file_code=? OR file_real=?",$code,$code)){$code = $ses->randchar(12);}

   $db->Exec("INSERT INTO Files 
        SET usr_id=?, 
            srv_id=?,
            file_fld_id=?,
            file_name=?, 
            file_descr=?, 
            file_public=?, 
            file_code=?, 
            file_real=?, 
            file_real_id=?, 
            file_del_id=?, 
            file_size=?,
            file_size_encoded=?,
            file_password=?, 
            file_ip=INET_ATON(?), 
            file_md5=?, 
            file_spec=?, 
            file_created=NOW(), 
            file_last_download=NOW()",
         $opts{usr_id}||$ses->getUserId,
         $file->{srv_id},
         $opts{fld_id}||0,
         $file->{file_name},
         '',
         1,
         $code,
         $file->{file_real},
         $file->{file_real_id}||$file->{file_id},
         $file->{file_del_id},
         $file->{file_size},
         $file->{file_size_encoded},
         $opts{file_password}||'',
         $opts{ip}||$ses->getIP,
         $file->{file_md5},
         $file->{file_spec}||'',
       );
   $db->Exec("UPDATE Servers SET srv_files=srv_files+1 WHERE srv_id=?",$file->{srv_id});
   return $code;
}

sub GetPremiumComparison
{
   # Do not modify $c directly to prevent affecting FastCGI
   my $ses = $Engine::Core::ses;

   my $limits = {%$c};
   for my $x ('max_upload_filesize')
   {
      for my $y ( 'anon', 'reg', 'prem' )
      {
         my $z = "$x\_$y";
         $limits->{$z} = $c->{$z} ? "$c->{$z} Mb" : "Unlimited";
      }
   }
   $limits->{max_downloads_number_reg}  = $c->{max_downloads_number_reg}  || 'Unlimited';
   $limits->{max_downloads_number_prem} = $c->{max_downloads_number_prem} || 'Unlimited';
   $limits->{files_expire_anon} =
     $c->{files_expire_access_anon}
     ? "$c->{files_expire_access_anon} $ses->{lang}->{lang_days_after_downl}"
     : $ses->{lang}->{lang_never};
   $limits->{files_expire_reg} =
     $c->{files_expire_access_reg}
     ? "$c->{files_expire_access_reg} $ses->{lang}->{lang_days_after_downl}"
     : $ses->{lang}->{lang_never};
   $limits->{files_expire_prem} =
     $c->{files_expire_access_prem}
     ? "$c->{files_expire_access_prem} $ses->{lang}->{lang_days_after_downl}"
     : $ses->{lang}->{lang_never};

   $limits->{disk_space_reg}  = $c->{disk_space_reg}  ? sprintf( "%.0f GB", $c->{disk_space_reg} / 1024 )  : "Unlimited";
   $limits->{disk_space_prem} = $c->{disk_space_prem} ? sprintf( "%.0f GB", $c->{disk_space_prem} / 1024 ) : "Unlimited";

   $limits->{bw_limit_anon} =
     $c->{bw_limit_anon}
     ? sprintf( "%.0f GB", $c->{bw_limit_anon} / 1024 ) . " in $c->{bw_limit_days} $ses->{lang}->{lang_days}"
     : 'Unlimited';
   $limits->{bw_limit_reg} =
     $c->{bw_limit_reg}
     ? sprintf( "%.0f GB", $c->{bw_limit_reg} / 1024 ) . " in $c->{bw_limit_days} $ses->{lang}->{lang_days}"
     : 'Unlimited';
   $limits->{bw_limit_prem} =
     $c->{bw_limit_prem}
     ? sprintf( "%.0f GB", $c->{bw_limit_prem} / 1024 ) . " in $c->{bw_limit_days} $ses->{lang}->{lang_days}"
     : 'Unlimited';

   for my $utype (qw(anon reg prem))
   {
      $limits->{"download_resume_$utype"} = $c->{m_n} ? $c->{"m_n_dl_resume_$utype"} : $c->{"direct_links_$utype"};
   }

   return $limits;
}

sub CheckForDelayedRedirects
{
   my ($user) = @_;
   return if !$user;

   my $ses = $Engine::Core::ses;
   my $db = $Engine::Core::db;

   if ( $user->{usr_notes} =~ /^payments/ )
   {
      $db->Exec( "UPDATE Users SET usr_notes='' WHERE usr_id=?", $user->{usr_id} );
      my $token = $ses->genToken(op => 'payments');
      return $ses->redirect("?op=payments&type=$1&amount=$2&target=$3&token=$token") if($user->{usr_notes} =~ /^payments-(\w+)-([\d\.]+)-([\w_]+)/);
      return $ses->redirect("?op=payments&type=$1&amount=$2&token=$token") if($user->{usr_notes} =~ /^payments-(\w+)-([\d\.]+)/);
   }

   return undef;
}

sub isVipFile
{
   my ($file) = @_;
   return 0 if $file->{file_price} <= 0;

   my $owner = $Engine::Core::db->SelectRow("SELECT *, usr_premium_expire > NOW() AS is_premium FROM Users WHERE usr_id=?", $file->{usr_id});
   return 1 if $owner->{usr_allow_vip_files};

   my $owner_utype = $owner->{is_premium} ? 'prem' : 'reg';
   return $c->{"allow_vip_files_$owner_utype"};
}

1;
