package Plugins::CDN::xfspro;
use vars qw($ses $db $c);
use strict;
use HCE_MD5;

sub options
{
   return
   {
      name=>'xfspro', title=>'XFileSharingPro',
   };
}

=item genDirectLink()
   Returns a link that leads to immediate file download
=cut
sub genDirectLink
{
   my ($self, $file, %opts) = @_;
   my $server = $ses->db->SelectRow("SELECT * FROM Servers WHERE srv_id=?", $file->{srv_id});
   return if $server->{srv_cdn};

   return &DlCGILink($file, %opts) if $opts{dl_method} eq 'cgi';
   return &UnixSymlink($file, %opts) if $opts{dl_method} eq 'symlink';

   return &NginxLink($file, %opts) if $c->{m_n};
   return &UnixSymlink($file, %opts) if $c->{"direct_links_$ses->{utype}"};
   return &DlCGILink($file, %opts);
}

sub delFiles
{
   my ($self, $srv_id, $files) = @_;
   my $server = $ses->db->SelectRow("SELECT * FROM Servers WHERE srv_id=?", $srv_id);
   return undef if $server->{srv_cdn};

   my $list = join ':', map{ "$_->{file_real_id}-$_->{file_real}" } @$files;
   my $res = $ses->api2($srv_id, { op => 'del_files', list => $list });
}

=item runTests()
   Returns true if it's OK to save the server
=cut
sub runTests
{
   my ($self, $f) = @_;
   return if $f->{srv_cdn};

   require LWP::UserAgent;
   my $ua = LWP::UserAgent->new(timeout => 15,agent=>'Opera/9.51 (Windows NT 5.1; U; en)');

   my @tests;
   my $fs_key = $db->SelectOne("SELECT srv_key FROM Servers WHERE srv_id=?",$f->{srv_id}) if $f->{srv_id};

   # max disk usage
   push @tests, 'max disk usage: ERROR' if !$f->{srv_disk_max} || $f->{srv_disk_max}<=0;

   # api.cgi multiple tests
   my $res = $ses->api($f->{srv_cgi_url}, { %{$f}, op => 'test', fs_key=>$fs_key, site_cgi=>$c->{site_cgi} } );
   if($res=~/^OK/)
   {
      push @tests, 'api.cgi: OK';
      $res=~s/^OK:(.*?)://;
      $f->{srv_ip} = $1;
      push @tests, split(/\|/,$res);
   }
   else
   {
      push @tests, "api.cgi: ERROR ($res)";
   }

   # upload.cgi
   $res = $ua->get("$f->{srv_cgi_url}/upload.cgi?mode=test");
   push @tests, $res->content eq 'XFS' ? 'upload.cgi: OK' : "upload.cgi: ERROR (problems with <a href='$f->{srv_cgi_url}/upload.cgi\?mode=test' target=_blank>link</a>)";

   # htdocs URL accessibility
   $res = $ua->get("$f->{srv_htdocs_url}/index.html");
   push @tests, $res->content eq 'XFS' ? 'htdocs URL accessibility: OK' : "htdocs URL accessibility: ERROR (should see XFS on <a href='$f->{srv_htdocs_url}/index.html' target=_blank>link</a>)";

   return @tests;
}

=item UnixSymlink()
   Generates a symlink URL (usually it's getting placed in files/ directory)
   Features:
      Speed limitation: no
      MP4/FLV streaming: depends on web server's configuration
      Download resuming: depends on web server's configuration
=cut

sub UnixSymlink
{
   my ($file, %opts) = @_;
   my $fname = $opts{file_name}||$file->{file_name};

   my $ip = $ses->getIP;
   $ip='' if $opts{link_ip_logic}||$c->{link_ip_logic} eq 'all';
   $ip=~s/\.\d+$// if $c->{link_ip_logic} eq 'first3';
   $ip=~s/\.\d+\.\d+$// if $c->{link_ip_logic} eq 'first2';

   my $orig = 1 if $file->{file_size_encoded} && !$opts{encoded};

   my $res = $ses->api($file->{srv_cgi_url},
                        {
	                        op           => 'gen_link',
	                        file_id      => $file->{file_real_id}||$file->{file_id},
	                        file_code    => $file->{file_real},
	                        file_code1   => $file->{file_code},
	                        file_name    => $fname,
	                        fs_key       => $file->{srv_key},
	                        ip           => $ip,
                           orig         => $orig,
                        });
   my ($ddcode) = $res=~/^OK:(.+)$/;
   unless($ddcode)
   {
           $ses->AdminLog("Error when creating symlink:($file->{srv_cgi_url})($file->{file_id})($file->{file_real})\n($res)");
           return $ses->message("Error happened when generating Download Link.<br>Please try again or Contact administrator.<br>($res)");
   }
   return "$file->{srv_htdocs_url}/$ddcode/$fname";
}

=item NginxLink()
   Generates download link for our customized version of Nginx (a.k.a. Nginx mod)
   Features:
      Speed limitation: yes
      MP4/FLV streaming: yes
      Download resuming: yes (also per-utype limitation is possible)
=cut

sub NginxLink
{
   my ($file, %opts) = @_;

   my $ip = $ses->getIP;
   my $link_ip_logic = $opts{link_ip_logic} || $c->{link_ip_logic} || 'exact';
   my $mask = _get_mask($link_ip_logic);

   my $hce = HCE_MD5->new($c->{dl_key},"XFileSharingPRO");
   my $usr_id = $ses->getUser ? $ses->getUserId : 0;
   my $dx = sprintf("%d",($file->{file_real_id}||$file->{file_id})/$c->{files_per_folder});
   my $orig = 1 if $file->{file_size_encoded} && !$opts{encoded};

   my $mode = {'anon'=>'f','reg'=>'r','prem'=>'p'}->{$ses->{utype}}||'f';
   my $hash = $ses->encode32( $hce->hce_block_encrypt(pack("SLLSA12ASC4LC4SSS",
                                   $file->{srv_id},
                                   $file->{file_id},
                                   $usr_id,
                                   $dx,
                                   $file->{file_real},
                                   $mode,
                                   $opts{speed}||$c->{down_speed},
                                   split(/\./,$ip),
                                   time+3600*$c->{symlink_expire},
                                   split(/\./,$mask),
                                   $orig,
                                   $opts{accept_ranges}||$c->{m_n_dl_resume},
                                   $opts{limit_conn}||$c->{m_n_limit_conn})) );
   my ($url) = $file->{srv_htdocs_url}=~/https?:\/\/([^\/:]+)/i;
   $opts{file_name}||=$file->{file_name};
   return "http://$url:182/d/$hash/$opts{file_name}";
}

=item DlCGILink()
   Generates download link for dl.cgi (fallback)
   Features:
      Speed limitation: yes
      MP4/FLV streaming: no
      Download resuming: no
=cut

sub DlCGILink
{
   my ($file, %opts) = @_;
   my $fname = $opts{file_name}||$file->{file_name};
   my $hce = HCE_MD5->new($c->{dl_key},"XFileSharingPRO");
   my $file_id = $file->{file_real_id}||$file->{file_id};

   my $orig = 1 if $file->{file_size_encoded} && !$opts{encoded};

   my $link_ip_logic = $opts{link_ip_logic} || $c->{link_ip_logic} || 'exact';
   my $mask = _get_mask($link_ip_logic);

   my $hash = $ses->encode32( $hce->hce_block_encrypt( pack("LA12SC4LC4SS",
      $file_id,
      $file->{file_real},
      $opts{speed}||$c->{down_speed},
      split(/\./,$ses->getIP),
      (time+$c->{symlink_expire}*3600),
      split(/\./,$mask),
      $orig,
      $opts{accept_ranges}||0)));

   $fname =~ s/([^A-Za-z0-9\-_\.!~*'\(\)\s])/ uc sprintf "%%%02x",ord $1 /eg;
   return "$file->{srv_cgi_url}/dl.cgi/$hash/$fname";
}

sub _get_mask
{
   my ($link_ip_logic) = @_;
   my $mask =
   {
      exact  => '255.255.255.255',
      first3 => '255.255.255.0',
      first2 => '255.255.0.0',
      all    => '0.0.0.0',
   }->{$link_ip_logic};

   die("Unknown IP logic: $link_ip_logic") if !$mask;

   return $mask;
}

1;
