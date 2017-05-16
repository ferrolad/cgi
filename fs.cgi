#!/usr/bin/perl
use strict;
use lib '.';
use XFileConfig;
use CGI::Simple;
$CGI::Simple::POST_MAX=-1;
use DataBase;
use Session;
use JSON;
use Log;

Log->new(filename => 'fs.log');

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

$SIG{__WARN__} = sub {};

#&Send("111") unless $ENV{REQUEST_METHOD} eq 'POST';

my $ses = Session->new;
my $f = $ses->f;
my $db = DataBase->new();

if($f->{op} eq 'test')
{
   print"Content-type:text/html\n\nOK:".$ses->getIP;
   exit;
}

my $server = $db->SelectRow("SELECT * FROM Servers WHERE srv_key=?", $f->{fs_key} );
&Send("333") unless $server;
#&Send("444") unless $server->{srv_ip} eq $ENV{REMOTE_ADDR};

&Stats if $f->{op} eq 'stats' && $c->{m_n_100_complete_percent};

sub Stats
{
   $|++;
   print"Content-type:text/html\n\n";
#   require Geo::IP;
#   my $gi = Geo::IP->new($Geo::IP::GEOIP_STANDARD);
   my $bandwidth_sum;

   for(split(/\n/,$f->{data}))
   {
      #&logg($_);
      my ($file_id,$usr_id,$ip,$bandwidth) = split(/\|/,$_);
      #next if $status eq '503';
      next unless $ip;
      #$ip = unpack('N',pack('C4', split('\.',$ip) ));

      my $file_rec=$db->SelectRow("SELECT *, u.usr_profit_mode
                                   FROM Files f
                                   LEFT JOIN Users u ON f.usr_id=u.usr_id
                                   WHERE f.file_id=?",$file_id);
      next unless $file_rec;

      my $file=$db->SelectRow("SELECT * FROM IP2Files
                               WHERE ip=?
                               AND usr_id=?
                               AND file_id=?",$ip,$usr_id,$file_id);

      ### What if no ip2file? e.g. IP changed
      if(!$file && $c->{m_y_embed_earnings})
      {
         logg("No IP2File record(ip=$ip)(file_id=$file_id)");
         $db->Exec("INSERT INTO IP2Files SET ip=?,
                               usr_id=?,
                               owner_id=?,
                               file_id=?",
                               $ip,
                               $usr_id,
                               $file_rec->{usr_id}||0,
                               $file_id);
         $file = {ip=>$ip, usr_id=>$usr_id, file_id=>$file_id, owner_id=>$file_rec->{usr_id}||0};
      }

      $file->{size} += $bandwidth;
      $bandwidth_sum+=$bandwidth;

      $db->Exec("UPDATE IP2Files
                 SET size=?
                 WHERE ip=? AND usr_id=? AND file_id=?",$file->{size},$ip,$usr_id,$file_id);

      my $ip2 = join '.', unpack('C4',pack('N', $ip ));
      logg("DL $file->{size} of $file_rec->{file_size} (ip=$ip2) (fin=$file->{finished})");

      ### If correctly finished download
      my $m_n_100_complete_percent = $c->{m_n_100_complete_percent} || 100;

      if( $file->{size} >= $file_rec->{file_size} * $m_n_100_complete_percent / 100 && 
          ###$file_rec->{file_ip} ne $ip && 
          !$file->{finished} )
      {
         my ($size_id,$money);
         my @ss = split(/\|/,$c->{tier_sizes});
         for(0..5){$size_id=$_ if defined $ss[$_] && $file_rec->{file_size}>=$ss[$_]*1024*1024;}
         require Geo::IP;
         my $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
         my $country = $gi->country_code_by_addr($ip2);
         if(defined $size_id)
         {
           my $tier_money = $c->{tier4_money};
           if   ($country=~/^($c->{tier1_countries})$/i){ $tier_money = $c->{tier1_money}; }
           elsif($country=~/^($c->{tier2_countries})$/i){ $tier_money = $c->{tier2_money}; }
           elsif($country=~/^($c->{tier3_countries})$/i){ $tier_money = $c->{tier3_money}; }
           $money = (split(/\|/,$tier_money))[$size_id];
         }
         $money = $money / 1000;
         $money=0 if $file_rec->{file_ip}==$ip;
         $money=0 if $file->{usr_id}==$file->{owner_id};

         my $owner = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $file_rec->{usr_id}) if $file_rec->{usr_id};
         if($owner && $ses->iPlg('p'))
         {
            $file_rec->{usr_profit_mode} = lc $file_rec->{usr_profit_mode};
            my $perc = $c->{"m_y_$file_rec->{usr_profit_mode}_dl"};
            $perc = 0 if $c->{m_y_manual_approve} && !$owner->{usr_aff_enabled};
            logg("perc=$perc");
            $money = $money*$perc/100;
         }
         $money=0 if $c->{max_money_last24} && 
                     $db->SelectOne("SELECT SUM(money) FROM IP2Files WHERE ip=? AND created>NOW()-INTERVAL 24 HOUR",$ip) >= $c->{max_money_last24};
         $money=sprintf("%.05f",$money);

        logg("Finished! ip=$ip2 usr_id=$usr_id file_id=$file_id Owner=$file_rec->{usr_id} Country=$country Money=$money");

        $db->Exec("UPDATE IP2Files
                   SET finished=1, money=?
                   WHERE ip=? AND usr_id=? AND file_id=?",$money,$ip,$usr_id,$file_id);

        $db->Exec("UPDATE LOW_PRIORITY Files 
                   SET file_downloads=file_downloads+1, 
                     file_money=file_money+?, 
                     file_last_download=NOW() 
                   WHERE file_id=?",$money,$file->{file_id});

        $db->Exec("UPDATE Users SET usr_money=usr_money+? WHERE usr_id=?",$money,$file_rec->{usr_id}) if $file_rec->{usr_id} && $money;

        $db->Exec("INSERT INTO Stats2
                   SET usr_id=?, day=CURDATE(),
                     downloads=1, profit_dl=$money
                   ON DUPLICATE KEY UPDATE
                     downloads=downloads+1, profit_dl=profit_dl+$money
                  ",$file_rec->{usr_id}) if $file_rec->{usr_id};

        $db->Exec("INSERT INTO Stats
              SET downloads=1, day=CURDATE()
              ON DUPLICATE KEY UPDATE
              downloads=downloads+1");

        if($file_rec->{usr_id} && $c->{referral_aff_percent} && $money)
        {
           my $aff_id = $db->SelectOne("SELECT usr_aff_id FROM Users WHERE usr_id=?",$file_rec->{usr_id});
           my $money2 = sprintf("%.05f",$money*$c->{referral_aff_percent}/100);
           $db->Exec("UPDATE Users SET usr_money=usr_money+? WHERE usr_id=?", $money2, $aff_id) if $aff_id && $money2;

           if($aff_id)
           {
	           $db->Exec("INSERT INTO Stats2
	                      SET usr_id=?, day=CURDATE(), profit_refs=$money2
	                      ON DUPLICATE KEY UPDATE profit_refs=profit_refs+$money2",$aff_id);
           }
        }

      }
   }

   $db->Exec("INSERT INTO Stats
              SET day=CURDATE(), bandwidth=?
              ON DUPLICATE KEY 
              UPDATE bandwidth=bandwidth+?",$bandwidth_sum,$bandwidth_sum) if $bandwidth_sum;
   print"OK";
   exit;
}

sub logg
{
   my $msg = shift;
   open(FILE,">>fs.log")||return;
   print FILE "$msg\n";
   #print "$msg\n";
   close FILE;
}


my $user;
my $session = $db->SelectRow("SELECT * FROM Sessions WHERE session_id=?", $f->{sess_id});
my $torrent = $db->SelectRow("SELECT * FROM Torrents WHERE sid=?", $f->{sid});

$user ||= &GetUser($torrent->{usr_id}) if $torrent;
$user ||= &GetUser($session->{usr_id}) if $session && $session->{usr_id};
$user ||= &GetUser($f->{usr_id}) if $f->{usr_id};
$user ||= &GetUser($db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?", $f->{usr_login})) if $f->{usr_login};

sub GetUser
{
   return $db->SelectRow("SELECT *, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec,
         (SELECT SUM(f.file_size) FROM Files f WHERE f.usr_id=u.usr_id) as total_size
         FROM Users u 
         WHERE u.usr_id=?",
         $_[0])
}

my $utype = $user ? ($user->{exp_sec}>0 ? 'prem' : 'reg') : 'anon';
$c->{$_}=$c->{"$_\_$utype"} for qw(disk_space max_upload_filesize max_rs_leech torrent_dl torrent_dl_slots remote_url);


my $sub={
         check_codes    => \&CheckCodes,
         update_srv     => \&UpdateServer,
         del_torrent    => \&TorrentDel,
         add_torrent    => \&TorrentAdd,
         torrent_stats  => \&TorrentStats,
         torrent_done   => \&TorrentDone,
         file_new_size  => \&FileNewSize,
         file_new_spec  => \&FileNewSpec,
         leech_mb_left  => \&LeechMBLeft,
         register_leeched => \&RegisterLeeched,
         transfer_progress    => \&TransferProgress,
         transfer_error       => \&TransferError,
         queue_transfer_next  => \&QueueTransferNext,
         queue_transfer_done  => \&QueueTransferDone,
        }->{ $f->{op} };
if($sub)
{
   &$sub;
}
else
{
   &SaveFile if $f->{file_name};
}

sub CheckCodes
{
   my @codes = split(/\,/,$f->{codes});
   print("Content-type:text/html\n\nOK:"),exit unless @codes;
   my $ok = $db->SelectARef("SELECT file_real FROM Files WHERE file_real IN (".join(',', map{"'$_'"}@codes ).")");
   my %h;
   $h{$_->{file_real}}=1 for @$ok;
   my @bad;
   for(@codes)
   {
      push @bad,$_ unless $h{$_};
   }
   print"Content-type:text/html\n\nOK:".join(',',@bad);
}

sub TorrentDel
{
   $db->Exec("DELETE FROM Torrents WHERE sid=?",$f->{sid});
   print"Content-type:text/html\n\nOK";
}

sub UpdateServer
{
   my $info = $db->SelectRow("SELECT srv_id, file_size, count(*) as num
                              FROM Files 
                              WHERE file_real=?
                              GROUP BY file_real",$f->{file_real});
   if(!$f->{file_md5}) {
      print"Content-type:text/html\n\nERROR: fileserver api <= 2.0";
      exit;
   }
   $db->Exec("UPDATE Files SET srv_id=? WHERE file_real=?",$f->{srv_id},$f->{file_real});
   $db->Exec("UPDATE Servers SET srv_files=srv_files-?, srv_disk=srv_disk-? WHERE srv_id=?",$info->{num},$info->{file_size},$info->{srv_id});
   $db->Exec("UPDATE Servers SET srv_files=srv_files+?, srv_disk=srv_disk+? WHERE srv_id=?",$info->{num},$info->{file_size},$f->{srv_id});
   print"Content-type:text/html\n\nOK";
}

sub TorrentAdd
{
   &Send("No sid") if !$f->{sid};
   print"Content-type:text/html\n\n";
   print("OK"),exit if $db->SelectOne("SELECT sid FROM Torrents WHERE sid=?",$f->{sid});
   print("ERROR:This type of users is not allowed to upload torrents"),exit unless $c->{torrent_dl};
   print("ERROR:You're already using $c->{torrent_dl_slots} torrent slots"),exit 
      if $c->{torrent_dl_slots} && $db->SelectOne("SELECT COUNT(*) FROM Torrents WHERE usr_id=? AND status='WORKING'",$user->{usr_id})>=$c->{torrent_dl_slots};

   $db->Exec("INSERT INTO Torrents SET sid=?, usr_id=?, srv_id=?, fld_id=?, link_rcpt=?, link_pass=?, progress='0:$f->{total_size}:0:0', created=NOW()",
              $f->{sid},
              $user->{usr_id},
              $server->{srv_id},
              $f->{fld_id}||0,
              $f->{link_rcpt}||'',
              $f->{link_pass}||'',
            );
   print"OK";
}

sub TorrentStats
{
   my $torrents = JSON::decode_json($f->{data});
   for(@$torrents)
   {
      $db->Exec("UPDATE Torrents SET progress=?, name=?, files=? WHERE sid=? AND status='WORKING'",
         "$_->{total_done}:$_->{total_wanted}:$_->{download_rate}:$_->{upload_rate}",
         $_->{name}||'',
         JSON::encode_json($_->{files}||[]),
         $_->{info_hash});
   }
   print"Content-type:text/html\n\nOK";
}

sub TorrentDone
{
   &Send("No sid") if !$f->{sid};
   my $torrent = $db->SelectRow("SELECT * FROM Torrents WHERE sid=?", $f->{sid});
   &Send("No torrent") if !$torrent;

   my $res = $ses->api2($server->{srv_id},
   {
      op => 'torrent_done',
      sid => $f->{sid},
      usr_id => $torrent->{usr_id},
   });
   print STDERR "Server return: $res\n";

   $db->Exec("DELETE FROM Torrents WHERE sid=?",$f->{sid});

   if($torrent->{link_rcpt})
   {
      my @files = split(/\n/, $torrent->{files});
      my $tmpl = $ses->CreateTemplate("confirm_email_user.html");
      $ses->SendMail( $f->{link_rcpt}, $c->{email_from}, "$c->{site_name}: File send notification", $tmpl->output() );
   }

   &Send('OK');
}

sub CheckFolder
{
   my ($path, $usr_id) = @_;
   my @path = split(/\/+/, $path);

   die("No usr_id") if !$usr_id;

   my $fld_id;
   my $parent_id = 0;
   for(@path)
   {
      next if $_ =~ /^\s*$/;
      if(!($fld_id = $db->SelectOne("SELECT fld_id FROM Folders WHERE fld_name=? AND usr_id=? AND fld_parent_id=?", $_, $usr_id, $parent_id)))
      {
         $db->Exec("INSERT INTO Folders SET fld_name=?, usr_id=?, fld_parent_id=?", $_, $usr_id, $parent_id);
         $fld_id = $db->getLastInsertId;
      }
      $parent_id = $fld_id;
   }

   return $fld_id;
}

sub SaveFile
{
   my $size  = $f->{file_size}||0;
   my $filename = $f->{file_name};
   my $descr = $f->{file_descr}||'';

   unless($f->{no_limits})
   {
      if( $c->{max_upload_filesize} && $size>$c->{max_upload_filesize}*1024*1024 )
      {
         print"Content-type:text/html\n\n";
         print"0:0:0:file is too big";
         exit;
      }
      $c->{disk_space} = $user->{usr_disk_space} if $user && $user->{usr_disk_space};
      if($c->{disk_space} && $user->{total_size}+$size > $c->{disk_space}*1048576)
      {
         print"Content-type:text/html\n\n";
         print"0:0:0:not enough disk space on your account";
         exit;
      }
      if($c->{fnames_not_allowed})
      {
          $filename=~s/$c->{fnames_not_allowed}/_/gi;
      }
      if($f->{rslee})
      {
         print("Content-type:text/html\n\n0:0:0:Remote upload is not allowed for you"),exit 
            unless $c->{remote_url};
         if($c->{max_rs_leech})
         {
            $c->{max_rs_leech} = $user->{usr_max_rs_leech} if $user;
            my $leech_left = $c->{max_rs_leech}*1048576 - $db->SelectOne("SELECT SUM(size) FROM IP2RS WHERE created>NOW()-INTERVAL 24 HOUR AND (usr_id=? OR ip=INET_ATON(?))",$user->{usr_id},$f->{file_ip});
            print("Content-type:text/html\n\n0:0:0:You've used all Remote traffic today"),exit 
               if $leech_left <= 0;
         }
         $db->Exec("INSERT INTO IP2RS SET usr_id=?, ip=INET_ATON(?), size=?",$user->{usr_id},$f->{file_ip},$size);
      }
      if( ($c->{ext_allowed} && $filename!~/\.($c->{ext_allowed})$/i) || ($c->{ext_not_allowed} && $filename=~/\.($c->{ext_not_allowed})$/i) )
      {
         print"Content-type:text/html\n\n";
         print"0:0:0:unallowed extension";
         exit;
      }
   }
   
   
   $filename=~s/%(\d\d)/chr(hex($1))/egs;
   $filename=~s/%/_/gs;
   $filename=~s/\s{2,}/ /gs;
   $filename=~s/[\#\"]+/_/gs;
   $filename=~s/[^\w\d\.-]/_/g if $c->{sanitize_filename};
   $filename=~s/\.(\w+)$/"$c->{add_filename_postfix}\.$1"/e if $c->{add_filename_postfix};
   $descr=~s/</&lt;/gs;
   $descr=~s/>/&gt;/gs;
   $descr=~s/\"/&quote;/gs;
   $descr=~s/\(/&#40;/gs;
   $descr=~s/\)/&#41;/gs;

   my $usr_id = $user ? $user->{usr_id} : 0;
   my $fld_id = $f->{fld_path} ? &CheckFolder($f->{fld_path}, $usr_id) : $f->{fld_id};
   
   my $md5 = $f->{file_md5}||'';
   my $code = &randchar(12);
   while($db->SelectOne("SELECT file_id FROM Files WHERE file_code=? OR file_real=?",$code,$code)){$code = &randchar(12);}
   my $del_id = &randchar(10);
   
   if($db->SelectOne("SELECT id FROM Reports WHERE ban_size=? AND ban_md5=? LIMIT 1",$size,$md5))
   {
      print"Content-type:text/html\n\n";
      print"0:0:0:this file is banned by administrator";
      exit;
   }

   if($c->{up_limit_days} && $ses->getUserLimit('up_limit', user => $user))
   {
      my $cond = $user ? "usr_id=".$user->{usr_id} : "file_ip=INET_ATON('$f->{file_ip}')";
      my $uploaded_last = $db->SelectOne("SELECT SUM(file_size) / POW(2,20)
            FROM Files
            WHERE $cond
            AND file_created > NOW() - INTERVAL ? DAY",
            $c->{up_limit_days});
      if($uploaded_last + ($size / 2**20) > $ses->getUserLimit('up_limit', user => $user))
      {
         print"Content-type:text/html\n\n";
         print"0:0:0:upload limit exceeded";
         exit;
      }
   }
   $db->SelectOne("SELECT SUM(file_size) FROM Files WHERE usr_id=? AND file_created > NOW() - INTERVAL 1 DAY");
   
   my $ex = $db->SelectRow("SELECT * FROM Files WHERE file_size=? AND file_md5=? AND file_real_id=0 LIMIT 1",$size,$md5)
            if $c->{anti_dupe_system};
   undef($ex) if $c->{m_e} && $filename =~ /\.(avi|divx|xvid|mpg|mpeg|vob|mov|3gp|flv|mp4|wmv|mkv)$/i;
   my $real = $ex->{file_real} if $ex;
   my $real_id = $ex->{file_id} if $ex;
   my $srv_id = $ex ? $ex->{srv_id} : $server->{srv_id};
   $f->{file_spec}=$ex->{file_spec} if $ex;
   #$server->{srv_id} = $ex->{srv_id} if $ex;
   $real ||= $code;

   my $file_awaiting_approve = 1 if $c->{files_approve};
   $file_awaiting_approve = 0 if $c->{files_approve_regular_only} && $user && $user->{usr_aff_enabled};
   
   $db->Exec("INSERT INTO Files 
              SET file_name=?, usr_id=?, srv_id=?, file_descr=?, file_fld_id=?, file_public=?, file_adult=?, file_code=?, file_real=?, file_real_id=?, file_del_id=?, file_size=?, 
                  file_password=?, file_ip=INET_ATON(?), file_md5=?, file_spec=?, file_awaiting_approve=?, file_upload_method=?, file_created=NOW(), file_last_download=NOW()",
               $filename,
               $usr_id,
               $srv_id,
               $descr,
               $fld_id||0,
               $f->{file_public}||0,
               $f->{file_adult}||0,
               $code,
               $real,
               $real_id||0,
               $del_id,
               $size,
               $f->{file_password}||'',
               $f->{file_ip}||'1.1.1.1',
               $md5,
               $f->{file_spec}||'',
               $file_awaiting_approve||0,
               $f->{file_upload_method}||'',
             );
   
   my $file_id = $db->getLastInsertId;
   $size=0 unless $code eq $real;
   $db->Exec("UPDATE Servers 
              SET srv_files=srv_files+1, 
                  srv_disk=srv_disk+?, 
                  srv_last_upload=NOW() 
              WHERE srv_id=?", $size, $srv_id );
   
   $db->Exec("INSERT INTO Stats SET day=CURDATE(), uploads=1 ON DUPLICATE KEY UPDATE uploads=uploads+1");

   if($session && $session->{api_key_id})
   {
	   $db->Exec("INSERT INTO APIStats SET key_id=?, day=CURDATE(),
	      uploads=1, bandwidth_in=?
	      ON DUPLICATE KEY UPDATE uploads=uploads+1, bandwidth_in=bandwidth_in+?",
         $session->{api_key_id}, $size, $size);
   }
   
   if($f->{compile})
   {
      my $file = $db->SelectRow("SELECT * FROM Files WHERE file_id=?", $file_id);
      my $link = $ses->makeFileLink($file);
      my $del_link="$link?killcode=$del_id";
      print"Content-type:text/html\n\n";
      print"$file_id:$code:$real:OK=$link|$del_link";
      exit;
   }
   
   print"Content-type:text/html\n\n";
   print"$file_id:$code:$real:OK";
}

sub FileNewSize
{
   my $file = $db->SelectRow("SELECT * FROM Files WHERE file_code=?",$f->{file_code});
   $db->Exec("UPDATE Files SET file_size=?, file_name=? WHERE file_code=?",$f->{file_size},$f->{file_name},$f->{file_code});
   $db->Exec("UPDATE Servers SET srv_disk=srv_disk+? WHERE srv_id=?",($f->{file_size}-$file->{file_size}),$file->{srv_id});
   print"Content-type:text/html\n\nOK";
}

sub FileNewSpec
{
   if($f->{file_code} && $f->{file_size} && $f->{preserve_orig})
   {
      $db->Exec("UPDATE Files 
                 SET file_spec=?, file_size_encoded=? 
                 WHERE file_real=?",$f->{file_spec},$f->{file_size},$f->{file_code});
   }
   elsif($f->{file_code} && $f->{file_size} && $f->{encoded})
   {
      my $ext = $c->{m_e_flv} ? 'flv' : 'mp4';
      $db->Exec("UPDATE Files 
                 SET file_name=CONCAT(file_name,'.$ext'), file_spec=?, file_size=? 
                 WHERE file_real=?",$f->{file_spec},$f->{file_size},$f->{file_code});
   }
   elsif($f->{file_code} && $f->{file_size})
   {
      $db->Exec("UPDATE Files 
                 SET file_spec=?, file_size=? 
                 WHERE file_real=?",$f->{file_spec},$f->{file_size},$f->{file_code});
   }
   elsif($f->{file_code})
   {
      $db->Exec("UPDATE Files 
                 SET file_spec=?
                 WHERE file_real=?",$f->{file_spec},$f->{file_code});
   }
   print"Content-type:text/html\n\nOK";
}

sub LeechMBLeft
{
   my $leech_left = $c->{max_rs_leech}*1048576 - $db->SelectOne("SELECT SUM(size) FROM IP2RS WHERE created>NOW()-INTERVAL 24 HOUR AND (usr_id=? OR ip=INET_ATON(?))",$user->{usr_id},$f->{file_ip});
   $leech_left=0 if $leech_left<0;
   print"Content-type:text/html\n\n";
   print"OK:$leech_left";
   exit ;
}

sub RegisterLeeched
{
   $db->Exec("INSERT INTO IP2RS SET usr_id=?, size=?, ip=?",
      $user->{usr_id},
      $f->{size},
      $f->{ip});
   &Send("OK");
}

sub QueueTransferNext
{
   my $filter_server = "AND srv_id2=?";
   $filter_server = "AND srv_id1=?" if $f->{direction} eq 'from';
   $filter_server = "AND ? IN (srv_id1, srv_id2)" if $f->{direction} eq 'both';
   my $filter_cdn = "AND s2.srv_cdn='$f->{cdn}'" if $f->{cdn};
   my $task = $db->SelectRow("SELECT * FROM QueueTransfer q
                              LEFT JOIN Servers s1 ON s1.srv_id = q.srv_id1
                              LEFT JOIN Servers s2 ON s2.srv_id = q.srv_id2
                              WHERE status='PENDING' 
                              $filter_server
                              $filter_cdn
                              LIMIT 1",
                              $server->{srv_id});
   &Send() unless $task;
   $db->Exec("UPDATE QueueTransfer SET status='MOVING', started=NOW() WHERE file_real=?",$task->{file_real});
   
   my $file = $db->SelectRow("SELECT *, s.srv_cgi_url, s.srv_htdocs_url
                              FROM Files f, Servers s
                              WHERE f.file_real=? 
                              AND f.srv_id=s.srv_id",$task->{file_real});
   
   $task->{dx} = sprintf("%05d",($file->{file_real_id}||$file->{file_id})/$c->{files_per_folder});
   $task->{file_real} = $file->{file_real};
   $task->{direct_link} = $ses->getPlugins('CDN')->genDirectLink($file, dl_method => 'cgi', link_ip_logic => 'all',
      encoded => $file->{file_size_encoded} ? 1 : 0);
   $task->{orig_link} = $ses->getPlugins('CDN')->genDirectLink($file, dl_method => 'cgi', link_ip_logic => 'all') if $file->{file_size_encoded};
   $task->{cdn_data} = $ses->getSrvData($task->{srv_id2});
   $task->{direction} = ($task->{srv_id1} == $server->{srv_id}) ? 'from' : 'to';
   $task->{$_} = $file->{$_} for qw(srv_htdocs_url);
   $task->{file_size} = $ses->api2($task->{srv_id1},
   {
      op => 'get_file_size',
      dx => $task->{dx},
      file_real => $task->{file_real},
   });
   $ses->getThumbLink($task) if $file->{file_name}=~/\.(jpg|jpeg|gif|png|bmp)$/i && $c->{m_i};
   if($c->{m_v} && $file->{file_name}=~/\.(avi|divx|mkv|flv|mp4|wmv)$/i)
   {
      my $dx = sprintf("%05d",($task->{file_real_id}||$file->{file_id})/$c->{files_per_folder});
      $task->{srv_htdocs_url}=~/(.+)\/.+$/;
      $task->{image_url}="$1/i/$dx/$file->{file_real}.jpg";
      $task->{thumb_url}="$1/i/$dx/$file->{file_real}_t.jpg";
   }

   &SendJSON($task);
}

sub QueueTransferDone
{
   my $task = $db->SelectRow("SELECT * FROM QueueTransfer WHERE file_real=?",$f->{file_real});
   my $file = $db->SelectRow("SELECT * FROM Files WHERE file_real=? LIMIT 1",$task->{file_real});

   $db->Exec("DELETE FROM QueueTransfer WHERE file_real=?",$f->{file_real});

   if($task->{copy})
   {
     $db->Exec("UPDATE Files SET srv_id_copy=? WHERE file_real=? LIMIT 200",$task->{srv_id2},$task->{file_real});
     &Send("OK=OK");
   }

   my $files_count = $db->SelectOne("SELECT COUNT(*) FROM Files WHERE file_real=?", $task->{file_real});
   $db->Exec("UPDATE Files SET srv_id=? WHERE file_real=?",$task->{srv_id2},$task->{file_real});
   $db->Exec("UPDATE Servers SET srv_files=srv_files-?, srv_disk=srv_disk-? WHERE srv_id=?",$files_count,$file->{file_size},$task->{srv_id1});
   $db->Exec("UPDATE Servers SET srv_files=srv_files+?, srv_disk=srv_disk+? WHERE srv_id=?",$files_count,$file->{file_size},$task->{srv_id2});

   require LWP::UserAgent;
   my $ua = LWP::UserAgent->new(agent => "XFS-FSServer", timeout => 900);
   my $srv_from = $db->SelectRow("SELECT * FROM Servers WHERE srv_id=?", $task->{srv_id1});
   my $res = $ua->post("$srv_from->{srv_cgi_url}/api.cgi", { op=>'del_files', fs_key => $srv_from->{srv_key}, list=>($file->{file_real_id}||$file->{file_id})."-".$file->{file_real} } )->content;
   &Send("OK=$res");
}

sub TransferProgress
{
   $db->Exec("UPDATE QueueTransfer SET updated=NOW(), transferred=?, speed=? WHERE file_real=?",$f->{transferred},$f->{speed},$f->{file_real});
   &Send("OK");
}

sub TransferError
{
    $db->Exec("UPDATE QueueTransfer 
               SET status='ERROR',
                   error=?,
                   speed=0,
                   transferred=0,
                   updated='0000-00-00 00:00:00'
               WHERE file_real=?",$f->{error},$f->{file_real});
    &Send("OK");
}

sub Send
{
   print"Content-type:text/html\n\n@_";
   exit;
}

sub SendJSON
{
   require JSON;
   print "Content-type:application/json\n\n", JSON::encode_json($_[0]);
   exit;
}

#################
sub randchar
{ 
   my @range = ('0'..'9','a'..'z');
   my $x = int scalar @range;
   join '', map $range[rand $x], 1..shift||1;
}
