#!/usr/bin/perl
### SibSoft.net ###
use strict;
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
use lib '.';
use XFSConfig;
use XUpload;
use CGI::Carp qw(fatalsToBrowser);
use CGI;
use LWP::UserAgent;
use HTTP::Cookies;
use HTML::Form;
use HTTP::Request::Common;
use File::Temp;
use File::Basename;
use URI;
use JSON;
use List::Util qw(max);
use Log;

Log->new(filename => 'upload.log');
$|++;

my ($upload_type) = $ENV{QUERY_STRING}=~/upload_type=([a-z]+)/;

print("Access-Control-Allow-Origin: *\n");
print("Content-type: text/plain\n\nOK"), exit if $ENV{REQUEST_METHOD} eq 'OPTIONS';

my $temp_dir = File::Temp::tempdir(DIR => $c->{temp_dir}, CLEANUP => 1);

my ($utype) = $ENV{QUERY_STRING}=~/utype=([a-z]+)/;
$c->{m_n_upload_speed} = $c->{"m_n_upload_speed_$utype"}||$c->{m_n_upload_speed_anon};

$MultipartBuffer::INITIAL_FILLUNIT = max(16 * 1024, $c->{m_n_upload_speed} * 2**10 * 0.1);
$CGITempFile::TMPDIRECTORY = $temp_dir;

sub throttleHook
{
   my ($fname, $buf, $offset) = @_;
   select(undef, undef, undef, length($buf) / ($c->{m_n_upload_speed} * 2**10)) if $c->{m_n_upload_speed};
}

my $cg = CGI->new(\&throttleHook);
my $f;
$f->{$_}=$cg->param($_) for $cg->param();

print("Content-type:text/html\n\nXFS"),exit if $ENV{QUERY_STRING}=~/mode=test/;

&kill_session() if $f->{kill};

$utype||=$cg->param('utype');
$utype||='anon';
$c->{$_}=$c->{"$_\_$utype"} for qw(enabled max_upload_files max_upload_filesize max_rs_leech remote_url leech remote_upload_speed);

print STDERR "Starting upload. Size: $ENV{'CONTENT_LENGTH'} Upload type: $upload_type\n";
my ($sid) = ($ENV{QUERY_STRING}=~/upload_id=(\d+)/); # get the random id for temp files

my @urls;

$c->{ip_not_allowed}=~s/\./\\./g;
if( $c->{ip_not_allowed} && &GetIP() =~ /^($c->{ip_not_allowed})$/ ) {
    &xmessage("ERROR: $c->{msg}->{ip_not_allowed}");
}
if(!$c->{enabled}) {
    &xmessage("ERROR: Uploads not enabled for this type of users");
}
if($c->{srv_status} ne 'ON') {
    &xmessage("ERROR: Server don't allow uploads at the moment");
}
if($c->{max_upload_filesize} && $ENV{CONTENT_LENGTH} > 1048576*$c->{max_upload_filesize}*$c->{max_upload_files}) {
    &xmessage("ERROR: $c->{msg}->{file_size_big}$c->{max_upload_filesize} Mb");
}

&TorrentUpload() if $f->{torr_on};

print "Content-type: application/json\n\n";
my @file_inputs;
@file_inputs = &URLUpload() if $upload_type eq 'url';
@file_inputs = &FileUpload() if !@file_inputs;

my @results = ProcessFiles(@file_inputs);
print JSON::encode_json(\@results);
exit();

sub ProcessFiles
{
    my @file_inputs = @_;
    my @files;

    $f->{ip} = &GetIP();
    $f->{torr_on}=1 if $f->{up1oad_type} eq 'tt';

    for my $file ( @file_inputs ) {
        $file->{file_status}="null filesize or wrong file path"
            if $file->{file_size}==0;

        $file->{file_status}="filesize too big"
            if $c->{max_upload_filesize} && $file->{file_size}>$c->{max_upload_filesize}*1048576;

        $file->{file_status}="too many files"
            if $#files>=$c->{max_upload_files};

        $file->{file_status}=$file->{file_error}
        if $file->{file_error};

# --------------------
        $file = &XUpload::ProcessFile($file, { %$f,
      file_upload_method => $upload_type eq 'file' ? 'web' : $upload_type
   }) unless $file->{file_status};
# --------------------

        $file->{file_status}||='OK';
        push @files, $file;
    }

    my @results = map { { file_code => $_->{file_code} || 'undef', file_status => $_->{file_status} } } @files;
    return @results;
}

sub leech_traffic_left
{
    my $ua2 = LWP::UserAgent->new(agent => "XFS-FSAgent", timeout => 90);
    my $res = $ua2->post("$c->{site_cgi}/fs.cgi", {
            op           => 'leech_mb_left',
            fs_key       => $c->{fs_key},
            sess_id      => $cg->param('sess_id')||'',
            file_ip      => $ENV{REMOTE_ADDR},
            })->content;
    return $1 if $res=~/^OK:(\d+)$/;
}

sub register_leeched_traffic
{
    my $ua2 = LWP::UserAgent->new(agent => "XFS-FSAgent", timeout => 90);
    my $res = $ua2->post("$c->{site_cgi}/fs.cgi", {
            op           => 'register_leeched',
            fs_key       => $c->{fs_key},
            sess_id      => $cg->param('sess_id')||'',
            size         => $_[0],
            ip           => $ENV{REMOTE_ADDR},
            })->content;
}

sub kill_session
{
    my $sid = $1 if $f->{kill} =~ /^(\d+)$/;
    &Send("No sid") if !$sid;

    my $session_data = "$c->{htdocs_tmp_dir}/$sid.json";
    open (FILE, $session_data) || &Send("No session data");
    my $jsonp = <FILE>;
    my $object = JSON::decode_json($1) if $jsonp =~ /update_stat\(({.*})\)/;
    close FILE;

    kill 9, $object->{pid};
    unlink($session_data);
    &Send("OK");
}

sub URLUpload
{
    require SessionF;
    require Plugin;

    my $ua = LWP::UserAgent->new(timeout => 90,
            requests_redirectable => ['GET', 'HEAD','POST'],
            agent   => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; ru; rv:1.9.1.6) Gecko/20091201 Firefox/3.5.6 (.NET CLR 3.5.30729)',
            protocols_allowed => ['http', 'https', 'ftp'],
            cookie_jar => HTTP::Cookies->new( hide_cookie2 => 1, ignore_discard => 1 ) );

    $Plugin::browser = $ua;

    my $ses = SessionF->new();
    $ses->LoadPlugins();

    my $logged_in = {};

    my $external_keys = {};
    for(split(/\|/, $c->{external_keys}))
    {
        my ($domain, $key) = split(/:/, $_, 2);
        $external_keys->{$domain} = $key;
    }

    sub randomize
    {
        my @lines = split(/\n\r?/, $_[0]);
        return $lines[int rand(@lines)];
    }

    sub computeName
    {
        # Figure out the resulting file_name in the same way as the browsers do
        my ($resp) = @_;
        my $content_disp = $resp->header('Content-Disposition');
        return $1 if $content_disp =~ /filename="(.+)"/
                    || $content_disp =~ /filename=(.+)/
                    || $content_disp =~ /filename\*=.*?''(.+)/;
        return $1 if URI->new($resp->request->uri)->path =~ /([^\/]+)$/;
    }

    sub Leech
    {
        my ($plugin, $url) = @_;
        $Plugin::tmpfile = "$c->{temp_dir}/".join('', map int rand(10), 1..10);

        my $uri = URI->new($url);
        my $userinfo = $uri->userinfo();
        $uri->userinfo('');

        my $prefix = $plugin->options->{plugin_prefix};
        my $can_login = $plugin->options->{plugin_prefix};
        my ($login, $pass) = split(':', $userinfo || $f->{"$prefix\_logins"} || &randomize($c->{"$prefix\_logins"}), 2);
        $plugin->login({ login => $login, password => $pass });

        my $ret = $plugin->download($uri->as_string, "", make_lwp_hook($sid));
        return { file_tmp => $Plugin::tmpfile, file_name_orig => $ret->{filename}, file_size => $ret->{filesize} };
    }

    sub ZeveraGetLink
    {
        my ($url) = @_;
        my ($login, $pass) = split(':', &randomize($c->{"zevera_logins"}), 2);

        my $ua = LWP::UserAgent->new(agent => 'XFileSharingPro', requests_redirectable => []);
        my $check = $ua->get("http://api.zevera.com/jDownloader.ashx?cmd=checklink&login=$login&pass=$pass&olink=$url")->decoded_content;
        return if $check ne 'Alive';

        return $ua
            ->get("http://api.zevera.com/jDownloader.ashx?cmd=generatedownloaddirect&login=$login&pass=$pass&olink=$url")
            ->header("Location");
    }

    sub APILeech
    {
        my ($domain, $url) = @_;
        my $file_code = $1 if $url =~ s/\/(\w{12}).*//;
        return { file_error => "File not found" } if !$file_code;

        my $res = $ua->post($url,
        {
            op => 'external',
            download => 1,
            api_key => $external_keys->{$domain},
            file_code => $file_code,
        });
        my $ret = JSON::decode_json($res->decoded_content);

        return &DirectDownload($ret->{direct_link});
    }

    sub DirectDownload
    {
        my ($url) = @_;
        $url = "http://$url" if($url !~ /^(\w+):\/\//);

        my $tempfile = "$c->{temp_dir}/".join('', map int rand(10), 1..10);
        open FILE, ">$tempfile"|| die"Can't open dest file:$!";
        my $req = HTTP::Request->new(GET => $url);
        my $resp = $ua->request($req, make_lwp_hook($sid));
        close FILE;

        if($c->{max_rs_leech})
        {
           return { file_error => 'No leech traffic left' } if leech_traffic_left() < $resp->content_length;
           register_leeched_traffic($resp->content_length);
        }
        
        if($resp->is_error)
        {
           return { file_error => 'Remote upload failed: ' . _secure_str($resp->status_line) };
        }

        my $filename = &computeName($resp);
        $filename=~s/%(\d\d)/chr(hex($1))/egs;

        return { file_tmp => $tempfile, file_name_orig => $filename, file_size => -s $tempfile };
    }

    my @file_inputs;
    for my $url(split(/\n\r?/, $f->{url_mass}))
    {
        my $domain = $1 if $url =~ /^https?:\/\/([^\/:]+)/; 
        my ($plugin) = grep { $_->check_link($url) } @{ $ses->getPlugins() };

        if($plugin && $c->{leech})
        {
           push @file_inputs, &Leech($plugin, $url);
        }
        elsif($external_keys->{$domain} && $c->{leech})
        {
            push @file_inputs, &APILeech($domain, $url);
        }
        elsif($c->{"zevera_logins"} && (my $direct_link = &ZeveraGetLink($url)))
        {
            print STDERR "Zevera URL: $direct_link\n";
            push @file_inputs, &DirectDownload($direct_link);
        }
        elsif($c->{remote_url})
        {
           push @file_inputs, &DirectDownload($url);
        }
        else
        {
            push @file_inputs, { file_status => "Not allowed" };
        }
    }

    return @file_inputs;
}

sub make_lwp_hook
{
   my ($sid) = @_;
   my ($total_size, $current_bytes, $old_time, $base_old, $fname2);
   my $files_uploaded = 0;

   sub hook_url
   {
      my ($buffer,$res) = @_;
      print FILE $buffer;
      $current_bytes+=length($buffer);

      if($c->{remote_upload_speed})
      {
         select(undef, undef, undef, length($buffer) / ($c->{remote_upload_speed} * 2**10)) if $c->{remote_upload_speed};
      }
   
      if(time>$old_time)
      {
         $total_size += $res->content_length if $base_old ne $res->base;
         $base_old = $res->base;
         $fname2 = $res->base;
         $old_time = time;

         print "# Keep-Alive\n" if $f->{keepalive};

         open(F,">$c->{htdocs_tmp_dir}/$sid.json");
         print F "update_stat(";
         print F JSON::encode_json(
            {
               pid => $$,
               state => "uploading",
               total => "$total_size",
               loaded => "$current_bytes",
               files_done => "$files_uploaded"
            });
         print F ")";
         close F;
      }
   };

   return \&hook_url;
}

sub FileUpload
{
    my @file_inputs;

    my %params;
    $params{$_} = [ $cg->param($_) ] for qw(file_descr file_public);

    for my $input( $cg->param() )
    {
        my @params = $cg->param($input);
        next unless my @file_names=$cg->upload($input);
        # HTML5 multi-upload support
        my $i = 0;
        foreach(@file_names)
        {
            my $u;
            ($u->{file_name_orig})=$cg->uploadInfo($_)->{'Content-Disposition'}=~/filename="(.+?)"/i;
            $u->{file_name_orig}=~s/^.*\\([^\\]*)$/$1/;
            $u->{file_size}   = -s $_;
            $u->{file_descr}  = shift @{ $params{'file_descr'} };
            $u->{file_public}  = shift @{ $params{'file_public'} };
            $u->{file_adult}  = shift @{ $params{'file_adult'} };
            $u->{file_tmp}    = $cg->tmpFileName($_);
            push @file_inputs, $u;
            $i++;
        }
    }

    return @file_inputs;
}

sub parseTorrent
{
    require BitTorrent;
    my $bt = BitTorrent->new();
    my $tt = $bt->getTrackerInfo($_[0]);

    my ($over,$files);
    foreach my $ff ( @{$tt->{files}} )
    {
        next if $ff->{name}=~/padding_file/;
        $over=1 if $ff->{size} > $c->{max_upload_filesize}*1048576;
        $files.="$ff->{name}:$ff->{size}\n";
    }

    &Send("One or more files in torrent exceed filesize limit of $c->{max_upload_filesize} Mb") if $c->{max_upload_filesize} && $over;
    return $tt->{hash};
}

sub TorrentUpload
{
    require TorrentClient;

    my $ua = LWP::UserAgent->new('XFS-FSAgent');
    my $tt = TorrentClient->new(fs_key => $c->{fs_key});

    my $hash;
    $hash = parseTorrent($cg->tmpFileName($f->{file_0})) if $f->{file_0};
    $hash = lc($1) if $f->{magnet} =~ /btih:([0-9a-zA-Z]+)/;

    my $res;

    if($f->{file_0})
    {
       my $file_tmp = $cg->tmpFileName($f->{file_0});
       $res = $tt->startdl(metainfo => [ $file_tmp ], fs_key => $c->{fs_key});
    }

    if($f->{magnet})
    {
       $res = $tt->startdl(magnet => $f->{magnet}, fs_key => $c->{fs_key});
    }

    if($res =~ /^OK/)
    {
       my $res = $ua->post("$c->{site_cgi}/fs.cgi", {
           op => 'add_torrent',
           sid => $hash,
           sess_id => $f->{sess_id},
           fs_key => $c->{fs_key},
           fld_id => $f->{fld_id}||0,
           link_rcpt => $f->{link_rcpt}||'',
           link_pass => $f->{link_pass}||'',
       });
   
       &Send("<b>Error while adding torrent:</b><br>" . $res->decoded_content) if $res->decoded_content !~ /^OK/i;
       print "Location: $c->{site_url}/?op=my_files\n";
       print "Status: 302\n";
    }
    else
    {
       print "Location: $c->{site_url}/?op=upload_result&st=Torrent%20engine%20is%20not%20running&fn=undef\n";
       print "Status: 302\n";
    }

    &XUpload::Send("OK");
}

#########################

unlink("$c->{htdocs_tmp_dir}/$sid.html");

#############################################

sub xmessage {
    print "Status: 500\n";
    print "Content-type: text/plain\n\n$_[0]";
    exit();
}

sub GetIP {
    return $ENV{REMOTE_ADDR};
}

sub _secure_str
{
   my ($str)=@_;
   $str=~s/</&lt;/gs;
   $str=~s/>/&gt;/gs;
   $str=~s/\"/&#x22;/gs;
   $str=~s/\'/&#x27;/gs;
   $str=~s/\(/&#40;/gs;
   $str=~s/\)/&#41;/gs;
   $str=~s/\0//gs;
   $str=~s/\\/\\\\/gs;
   return $str;
}
