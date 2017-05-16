#!/usr/bin/perl
use strict;
use XFileConfig;
use Session;
use CGI::Carp qw(fatalsToBrowser);
use XUtils;
use List::Util qw(sum min);

$SIG{__WARN__} = sub {};
my $ses = Session->new();
my $db= $ses->db;

if($ENV{REQUEST_METHOD})
{
   # Script is requested through the web interface, so checking for the admin priviliges
   my $user = XUtils::CheckAuth($ses, $ses->getCookie( $ses->{auth_cook} ));
   $ses->message("Access denied"), exit if !$user || !$user->{usr_adm};
}

$|++;
print"Content-type:text/html\n\n";

$db->Exec("INSERT INTO Misc SET name='last_cron_time', value=? ON DUPLICATE KEY UPDATE value=?",time,time);

my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_status<>'OFF'");

# Delete expired symlinks
for my $srv (@$servers)
{
   print"Deleting symlinks for SRV=$srv->{srv_id}...";
   my $res = $ses->api($srv->{srv_cgi_url},
                       {
                          fs_key => $srv->{srv_key},
                          op     => 'expire_sym',
                          hours  => $c->{symlink_expire},
                       }
                      );
   if($res=~/OK/)
   {
      print"Done.<br>\n";
   }
   else
   {
      print"Error when deleting syms. SRV=$srv->{srv_id}.<br>\n$res<br><br>";
      $ses->AdminLog("Error when deleting syms. ServerID: $srv->{srv_id}.\n$res");
   }
   
}

my %to_expire;

for my $srv(@$servers)
{
   my $srv_id = $srv->{srv_id};
   my $filter_ext = "f.file_name NOT RLIKE '\.($c->{ext_not_expire})\$'" if $c->{ext_not_expire};
   if($c->{files_expire_access_anon})
   {
      push @{ $to_expire{$srv_id} }, selectFiles($srv_id, $c->{files_expire_access_anon}, "f.usr_id=0", $filter_ext);
   }
   if($c->{files_expire_access_reg})
   {
      push @{ $to_expire{$srv_id} }, selectFiles($srv_id, $c->{files_expire_access_reg}, "usr_premium_expire < NOW()-INTERVAL 3 DAY", $filter_ext);
   }
   if($c->{files_expire_access_prem})
   {
      push @{ $to_expire{$srv_id} }, selectFiles($srv_id, $c->{files_expire_access_prem}, "usr_premium_expire >= NOW()", $filter_ext);
   }
}

my $current_time = $db->SelectOne("SELECT UNIX_TIMESTAMP()");
my $files_count = $db->SelectOne("SELECT COUNT(*) FROM Files");
my $files_to_delete = sum( map { int(@{ $_ }) } values(%to_expire) );
my $confirmation_needed = 1 if $files_count > 5000 && $files_to_delete > $files_count * 0.05;
my $mass_del_confirm_response = $db->SelectOne("SELECT UNIX_TIMESTAMP(updated) FROM Misc WHERE name='mass_del_confirm_response'");
my $has_confirmation = $mass_del_confirm_response && ($current_time < $mass_del_confirm_response + 24 * 3600);

$db->Exec("DELETE FROM Misc WHERE name='mass_del_confirm_response'") if $files_to_delete == 0;

print "Total files count: $files_count To delete: $files_to_delete Confirmation needed: $confirmation_needed Has confirmation: $has_confirmation<br>\n";

if($confirmation_needed && !$has_confirmation)
{
   open(FILE, ">$c->{cgi_path}/temp/expiry_confirmation.csv") || die("Couldn't open file: $!");
   print FILE join(",", qw(url created last_download days_ago user_name user_type file_name)), "\n";

   my @array;
   push @array, @{ $to_expire{$_} } for keys(%to_expire);
   @array = sort { $b->{file_last_download} cmp $a->{file_last_download} } @array;

   for(@array)
   {
      my $usr_login = $_->{usr_login}||'-';
      my $utype = $_->{usr_login} ? ($_->{is_prem} ? 'prem' : 'reg') : 'anon';
      print FILE "$c->{site_url}/$_->{file_code},$_->{file_created},$_->{file_last_download},$_->{days_ago} days ago,$usr_login,$utype,$_->{file_name}\n";
   }
   close(FILE);

   $db->Exec("INSERT INTO Misc SET name='mass_del_confirm_request', value='$files_to_delete' ON DUPLICATE KEY UPDATE value='$files_to_delete'");
}
else
{
   for my $srv_id (keys %to_expire)
   {
      my @list = @{ $to_expire{$srv_id} };
      my @portion = @list[0..min($#list, 7000)];
      print int(@list), " files to delete from srv#$srv_id, ", int(@portion), " in this portion<br>\n";
      $ses->DeleteFilesMass(\@portion) if @portion;
   }
}

sub selectFiles
{
   my ($srv_id, $expire_after, @filters) = @_;
   @filters = grep { $_ } @filters;
   return if !$srv_id || !$expire_after || !@filters;

   my $sql_filters = join(' ', map { "AND $_"} @filters);

   my $list = $db->SelectARef("SELECT f.*,
            u.usr_login,
            u.usr_premium_expire > NOW() AS is_prem,
            TIMESTAMPDIFF(DAY, file_last_download, NOW()) AS days_ago
            FROM Files f
            LEFT JOIN Users u ON u.usr_id=f.usr_id
            WHERE srv_id=?
            AND file_last_download < NOW()-INTERVAL ? DAY
            $sql_filters",
            $srv_id,
            $expire_after);
   return @$list;
}

if($c->{dmca_expire})
{
   my $reports = $db->SelectARef("SELECT f.* FROM Reports r
                                    LEFT JOIN Users u ON u.usr_id=r.usr_id
                                    LEFT JOIN Files f ON f.file_id=r.file_id
                                    WHERE r.status='PENDING'
                                    AND u.usr_dmca_agent
                                    AND r.created < NOW() - INTERVAL ? HOUR
                                    AND f.file_id
                                    GROUP BY r.file_id",
                                    $c->{dmca_expire});

   print int(@$reports), " files to delete by DMCA reports\n";
   $db->Exec("UPDATE Reports SET status='APPROVED' WHERE file_id=?", $_->{file_id}) for @$reports;
   $ses->DeleteFilesMass($reports) if @$reports;
}

if($c->{trash_expire})
{
   my $trashed = $db->SelectARef("SELECT * FROM Files
                        WHERE file_trashed > 0
                        AND file_trashed < NOW() - INTERVAL ? HOUR
                        LIMIT 5000",
                        $c->{trash_expire});
   print int(@$trashed), " files to delete from trash\n";
   $ses->DeleteFilesMass($trashed) if @$trashed;

   my $trashed_folders = $db->SelectARef("SELECT * FROM Folders WHERE fld_trashed");

   for(@$trashed_folders)
   {
      $db->Exec("DELETE FROM Folders WHERE fld_id=?", $_->{fld_id}) if $ses->getFilesTotal($_->{fld_id}) eq '0';
   }
}

# Delete old reports
$db->Exec("DELETE FROM Reports WHERE created<NOW() - INTERVAL 3 MONTH");

$db->Exec("DELETE FROM IP2RS WHERE created<NOW() - INTERVAL 7 DAY");
$db->Exec("DELETE FROM Sessions WHERE last_time<NOW() - INTERVAL 3 DAY");

if($c->{clean_ip2files_days})
{
   $db->Exec("DELETE FROM IP2Files WHERE created<NOW() - INTERVAL ? DAY LIMIT 5000",$c->{clean_ip2files_days});
}

$db->Exec("DELETE FROM DelReasons WHERE last_access<NOW() - INTERVAL 6 MONTH");
$db->Exec("DELETE FROM LoginProtect where created < NOW() - INTERVAL 1 HOUR");

### Clean old image captchas ###
if($c->{captcha_mode}==1)
{
   opendir(DIR, "$c->{site_path}/captchas");
   while( defined(my $fn=readdir(DIR)) )
   {
      next if $fn=~/^\.{1,2}$/;
      my $file = "$c->{site_path}/captchas/$fn";
      unlink($file) if (time -(lstat($file))[9]) > 1800;
   }
   closedir DIR;
}
######
 
### Receive text-link-ads ###
if($c->{tla_xml_key})
{
   my $XML_FILENAME = "$c->{cgi_path}/Templates/text-link-ads.html";
   my ($file_size,$file_mod) = (stat ($XML_FILENAME) )[7,9];
   if(($file_mod < time - 3600) || $file_size < 20)
   {
      print"Getting TLA...<br>\n";
      require XML::Simple;
      require LWP::UserAgent;
      my $now = time;
      utime $now, $now, ($XML_FILENAME);
      my $ua = LWP::UserAgent->new(timeout => 90);
      my $res = $ua->get("http://www.text-link-ads.com/xml.php?inventory_key=$c->{tla_xml_key}&referer=" . $ses->{cgi_query}->url_encode($c->{site_url}) . "&user_agent=" . $ses->{cgi_query}->url_encode('Opera/10.00 (Windows NT 5.1; U; Edition Turbo; en) Presto/2.2.0'));
      my ($ads,$temp);
      my $xml = new XML::Simple;
      my $data = $xml->XMLin($res->content);
      if ($data->{'Link'})
      {
         if(ref $data->{'Link'} eq "HASH"){@$temp = ($data->{'Link'});$data->{'Link'} = $temp;}
        my $proc = sprintf("%.0f", 100/scalar(@{$data->{'Link'}}) );
        $ads='<div style="margin-bottom:5px;">';
        if ($data->{'Link'}->[0])
        {
            for(@{$data->{'Link'}})
            {
               $ads.="<span style='margin-left:20px;'>" . (( ref $_->{'BeforeText'} eq "HASH") ? "" : $_->{'BeforeText'} ) . " <a href=\"$_->{'URL'}\">$_->{'Text'}</a> " . (( ref $_->{'AfterText'} eq "HASH") ? "" : $_->{'AfterText'} ) . "</span>\n";
            }
            $ads.="</div>";
         }
      }
      open F, ">$c->{cgi_path}/Templates/text-link-ads.html";
      print F $ads;
      close F;
   }
}


if($c->{ping_google_sitemaps})
{
   my ($file_size,$file_mod) = (stat ("$c->{site_path}/sitemap.txt.gz") )[7,9];
   if(($file_mod < time - 3600) || $file_size < 20)
   {
      print"Generating Google Sitemap...<br>\n";
      open(F, ">$c->{site_path}/sitemap.txt")||die"can't open sitemap.txt";
      my $cx=0;
      while( my $files=$db->Select("SELECT file_code,file_name
                                    FROM Files
                WHERE file_public
                                    LIMIT $cx,200") )
      {
         $cx+=200;
         last if $cx>50000;
         $files=[$files] unless ref($files) eq 'ARRAY';
         for(@$files)
         {
            print F $ses->makeFileLink($_),"\n";
         }
      }
      close F;
      `gzip -c $c->{site_path}/sitemap.txt > $c->{site_path}/sitemap.txt.gz`;
      require LWP::UserAgent;
      my $ua = LWP::UserAgent->new();
      $ua->get( "http://www.google.com/webmasters/tools/ping?sitemap=".$ses->{cgi_query}->url_encode("$c->{site_url}/sitemap.txt.gz") );
   }
}

if($c->{cron_test_servers})
{
   $c->{email_text}=1;
   my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_status<>'OFF' AND srv_cdn=''");
   for my $s (@$servers)
   {
      print"Checking server $s->{srv_name}...";
      my $res = $ses->api($s->{srv_cgi_url}, {op => 'test', fs_key=>$s->{srv_key}, site_cgi=>$c->{site_cgi}} );
      my ($error, $tries);
      for(split(/\|/,$res))
      {
         $error=1 if /ERROR/;
      }
      my $key = "srv_tries_$s->{srv_id}";
      if($error || $res!~/^OK/)
      {
         $res=~s/\|/\n/gs;
         print"Server error:$res\n";
         $db->Exec("INSERT INTO Misc SET name=?, value=1
            ON DUPLICATE KEY UPDATE value=value+1", $key);
         $tries = $db->SelectOne("SELECT value FROM Misc WHERE name=?", $key);
      } else {
         $db->Exec("UPDATE Misc SET value=0 WHERE name=?", $key);
      }
      if($tries > 3)
      {
         print"Sending mail\n";
         $ses->SendMail($c->{contact_email}, $c->{email_from}, "$s->{srv_name} server error","Error happened while testing server $s->{srv_name}:\n\n$res");
      }
      else
      {
         print"OK\n";
      }
   }
}

# Generate static last-news template
if($c->{show_last_news_days})
{
   my $news = $ses->db->SelectARef("SELECT * FROM News WHERE created > NOW()-INTERVAL ? DAY ORDER BY created DESC",$c->{show_last_news_days});
   my $t=$ses->CreateTemplate( "last_news.html" );
   $t->param(news_list => $news);
   open(FILE,">$c->{cgi_path}/Templates/static/last_news.html") || die"can't write to Templates/static/last_news.html";
   print FILE $t->output;
   close FILE;
}
elsif(-s "$c->{cgi_path}/Templates/static/last_news.html")
{
   open(FILE,">$c->{cgi_path}/Templates/static/last_news.html");
   close FILE;
}

if($c->{torrent_autorestart})
{
   my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_torrent=1");
   for(@$servers)
   {
      my $res = $ses->api2($_->{srv_id},{ op => 'torrent_status' });
      unless($res eq 'ON')
      {
         require LWP::UserAgent;
         my $ua = LWP::UserAgent->new(timeout=>30);
         $ua->get("$_->{srv_cgi_url}/Torrents/bitflu.pl");
      }
   }
}

=pod
if($c->{ftp_mod}) {
   # Deprecated in a favor of new integration scheme
}
=cut

print"-----------------------<br>ALL DONE<br><br><a href='$c->{site_url}/?op=admin_servers'>Back to server management</a>";
