package XUtils;
use strict;
use XFileConfig;
use JSON;

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

      refuse('MAX24_REACHED') if $c->{max_money_last24} && $db->SelectOne("SELECT SUM(money) FROM IP2Files WHERE ip=? AND created>NOW()-INTERVAL 24 HOUR",$opts{ip}) >= $c->{max_money_last24};
      refuse('MAX24_REACHED') if $c->{max_paid_dls_last24} && $db->SelectOne("SELECT COUNT(*) FROM IP2Files WHERE ip=? AND created>NOW()-INTERVAL 24 HOUR AND money > 0",$opts{ip}) >= $c->{max_paid_dls_last24};
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
                  ip=?, 
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

   if($c->{hold_profits_interval})
   {
      $db->Exec("INSERT INTO HoldProfits SET day=CURDATE(), usr_id=?, amount=?
         ON DUPLICATE KEY UPDATE amount=amount+?",
         $file->{usr_id}, $money, $money);
   }
   else
   {
      $db->Exec("UPDATE LOW_PRIORITY Users SET usr_money=usr_money+? WHERE usr_id=?",$money,$file->{usr_id}) if $file->{usr_id} && $money;
   }

   $total_money_charged += $money if $file->{usr_id};

   if($c->{m_p_show_downloads_mode} ne 'show_only_paid' || $money > 0)
   {
      $db->Exec("INSERT INTO Stats2
                 SET usr_id=?, day=CURDATE(),
                     downloads=1, profit_dl=$money
                 ON DUPLICATE KEY UPDATE
                     downloads=downloads+1, profit_dl=profit_dl+$money
                ",$file->{usr_id}) if $file->{usr_id};
   }

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

   $db->Exec("INSERT INTO Reports SET file_id=?, usr_id=?, filename=?, name=?, email=?, reason=?, info=?, ip=?, status='PENDING', created=NOW()",
      $file->{file_id},
      $ses->getUserId,
      $file->{file_name},
      $ses->getUser->{usr_login},
      $ses->getUser->{usr_email},
      'Mass DMCA',
      '',
      $ses->getIP);
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
      my $cond = $Engine::Core::ses->getUser ? "usr_id=".$Engine::Core::ses->getUserId : "ip='".$Engine::Core::ses->getIP."'";
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
      my $cond = $Engine::Core::ses->getUser ? "usr_id=".$Engine::Core::ses->getUserId : "ip='".$Engine::Core::ses->getIP."'";
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

   if(($owner->{usr_premium_only} || $file->{file_premium_only}) && $Engine::Core::ses->{utype} ne 'prem')
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
   my $list = $Engine::Core::db->SelectARef("SELECT *, cmt_ip as ip, DATE_FORMAT(created,'%M %e, %Y') as date, DATE_FORMAT(created,'%r') as time
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
   
   if(!$Engine::Core::db->SelectOne("SELECT file_id FROM IP2Files WHERE file_id=? AND ip=? AND usr_id=?",$file->{file_id},$Engine::Core::ses->getIP,$usr_id))
   {
      $f->{referer}||= $Engine::Core::ses->getCookie('ref_url') || $Engine::Core::ses->getEnv('HTTP_REFERER');
      $f->{referer}=~s/$c->{site_url}//i;
      $f->{referer}=~s/^http:\/\///i;

      if($c->{m_n_100_complete_percent})
      {
         # Don't charge any money, leave it for fs.cgi instead
         $Engine::Core::db->Exec("INSERT INTO IP2Files SET 
               file_id=?, usr_id=?, owner_id=?, ip=?, size=0, referer=?, status=?",      
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
         ? "AND usr_lastip='$f->{key}'"
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
