#!/usr/bin/perl
use strict;
use lib '.';
use XFSConfig;
use CGI::Carp qw(fatalsToBrowser);
use CGI;
use File::Path;
use LWP::UserAgent;
use HTTP::Request::Common;
$HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
use File::Copy;
use Digest::MD5;
use XUpload;
use File::Temp qw(tempfile tempdir);
use File::Basename;
use File::Find;
use Data::Dumper qw(Dumper);
use JSON;
use Cwd;
use Log;

Log->new(filename => 'api.log');

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

#die"Error1" unless $ENV{REQUEST_METHOD} eq 'POST';

my $q = CGI->new();
my $f;
$f->{$_}=$q->param($_) for $q->param;

&CompileChunks if $f->{op} eq 'compile';## && $ENV{HTTP_USER_AGENT} eq 'XFS-FSUploader';

&Send( "OK:0:ERROR: fs_key is wrong or not empty") if $f->{fs_key} ne $c->{fs_key};

#die"Error2" unless $ENV{HTTP_USER_AGENT} eq 'XFS-FSServer';

my $sub={
         gen_link       => \&GenerateLink,
         expire_sym     => \&ExpireSymlinks,
         del_files      => \&DeleteFiles,
         test           => \&Test,
         update_conf    => \&UpdateConfig,
         check_files    => \&CheckFiles,
         get_files_list => \&GetFilesList,
         get_file_stats => \&GetFileStats,
         import_list    => \&ImportList,
         import_list_do => \&ImportListDo,
         torrent_delete => \&TorrentDelete,
         torrent_kill   => \&TorrentKill,
         torrent_status => \&TorrentStatus,
         torrent_done   => \&TorrentDone,
         rar_password   => \&rarPasswordChange,
         rar_file_del   => \&rarProcess,
         rar_file_extract => \&rarProcess,
         rar_split      => \&rarProcess,
         get_file_size  => \&GetFileSize,
         reencode       => \&Reencode,
         rethumb        => \&Rethumb,
         start_seeding  => \&StartSeeding,
	}->{ $f->{op} };
if($sub)
{
   &$sub;
}
else
{
   die"Error4";
}


sub GenerateLink
{
   my $file_code = $f->{file_code};
   my $file_name = $f->{file_name};
   my $ip        = $f->{ip};
   my $dx = sprintf("%05d",$f->{file_id}/$c->{files_per_folder});
   &Send("ERROR:no_file") unless -f "$c->{upload_dir}/$dx/$file_code";
   my $x1 = int(rand(10));
   my $rand = &randchar(14);
   unless(-d "$c->{htdocs_dir}/$x1")
   {
      mkdir("$c->{htdocs_dir}/$x1") || &Send("ERROR:mkdir0");
      chmod 0777, "$c->{htdocs_dir}/$x1";
   }
   $rand="$x1/$rand";
   while(-d "$c->{htdocs_dir}/$rand"){$rand = &randchar(14);}
   mkdir("$c->{htdocs_dir}/$rand") || &Send("ERROR:mkdir");
   chmod 0777, "$c->{htdocs_dir}/$rand";
   symlink("$c->{upload_dir}/$dx/$file_code","$c->{htdocs_dir}/$rand/$file_name") || &Send("ERROR:sym_create_failed");

   if($ip)
   {
      open(FILE,">$c->{htdocs_dir}/$rand/.htaccess");
      $ip=~s/\./\\./g;
      $file_name=~s/\s/_/g;
      print FILE qq[RewriteEngine on\nRewriteCond %{REMOTE_ADDR} !^$ip\nRewriteRule ^.*\$ "$c->{site_url}/404.html?$c->{site_url}/$f->{file_code1}/$file_name.html"];
      close FILE;
   }

   &Send("OK:$rand");
}

sub ExpireSymlinks
{
   my $hours = $f->{hours};
   &daemonize;
   $|++;
   print"Content-type:text/html\n\n";
   for my $i (0..9)
   {
      next unless -d "$c->{htdocs_dir}/$i";
      opendir(DIR, "$c->{htdocs_dir}/$i") || next;
      my $time = time;
      while( defined(my $fn=readdir(DIR)) )
      {
         next if $fn =~ /^\.{1,2}$/;
         my $file = "$c->{htdocs_dir}/$i/$fn";
         my $ftime = (lstat($file))[9];
         next if ($time - $ftime) < 3600*$hours;
         if(-f $file)
         {
            unlink($file);
         }
         else
         {
            rmtree($file);
         }
         print"\n";
      }
      closedir(DIR);
   }
   print"OK";
   exit;
}

sub DeleteFiles
{
   my $list = $f->{list};
   &Send('OK') unless $list;
   &daemonize;
   $|++;
   print"Content-type:text/html\n\n";
   my @arr = split(/:/,$list);
   my $idir = $c->{htdocs_dir};
   $idir=~s/^(.+)\/.+$/$1\/i/;
   for my $x (@arr)
   {
      my ($file_id,$file_code)=split('-',$x);
      my $dx = sprintf("%05d",$file_id/$c->{files_per_folder});
      unlink("$c->{upload_dir}/$dx/$file_code") if -f "$c->{upload_dir}/$dx/$file_code";
      unlink <$idir/$dx/$file_code*>;
      print"\n";
   }
   print"OK";
   exit;
}

sub CheckFiles
{
   my @files = @{ JSON::decode_json($f->{files}) };
   $_->{dx} = sprintf("%05d",$_->{file_real_id}||$_->{file_id}/$c->{files_per_folder}) for @files;
   my @nofiles = grep { ! -f "$c->{upload_dir}/$_->{dx}/$_->{file_real}" } @files;
   &SendJSON( \@nofiles );
}

sub GetFileSize
{
   my $path = "$c->{upload_dir}/$f->{dx}/$f->{file_real}";
   &Send(-s $path);
}

sub GetFilesList
{
   my $dx = sprintf("%05d", $f->{dx});
   local *ls = sub { [ map { basename($_) } glob($_[0]) ] };
   &SendJSON(ls("$c->{upload_dir}/$dx/*")) if $f->{dx} ne ''; # List files
   &SendJSON(ls("$c->{upload_dir}/*")); # List directories
}

sub GetFileStats
{
   opendir(DIR, "$c->{upload_dir}") || &Send("Error:cant open upload_dir");
   my ($files,$size)=(0,0);
   while( defined(my $fn=readdir(DIR)) )
   {
      next if $fn=~/^\.{1,2}$/ || !-d "$c->{upload_dir}/$fn";
      opendir(DIR2, "$c->{upload_dir}/$fn")||next;
      foreach my $fn2 (readdir(DIR2))
      {
         next if $fn2 =~ /^\.{1,2}$/;
         $files++;
         $size += -s "$c->{upload_dir}/$fn/$fn2";
      }
      closedir(DIR2);
   }
   &Send("OK:$files:$size");
}

sub ImportList
{
   opendir(DIR, "$c->{cgi_dir}/ImportFiles") || &Send("Error:cant open ImportFiles dir");
   my @arr;
   while( defined(my $fn=readdir(DIR)) )
   {
      next if $fn=~/^\.{1,2}$/;
      next unless -f "$c->{cgi_dir}/ImportFiles/$fn";
      push @arr, $fn.'-'.(-s "$c->{cgi_dir}/ImportFiles/$fn");
   }
   &Send("OK:".join(':',@arr));
}

sub ImportListDo
{
   my $usr_id = $f->{usr_id};
   my $pub    = $f->{pub};
   my $import_dir = "$c->{cgi_dir}/ImportFiles";
   opendir(DIR, $import_dir) || &Send("Error:cant open ImportFiles dir:$!");
   my $ua = LWP::UserAgent->new(keep_alive => 1,agent => "XFS-FSAgent",timeout => 180,);
   my $cx=0;
   require XUpload;
   while( defined(my $fn=readdir(DIR)) )
   {
      next if $fn=~/^\.{1,2}$/;
      next unless -f "$import_dir/$fn";

      my $file = {file_tmp=>"$import_dir/$fn", file_name_orig=>$fn, file_public=>$pub, usr_id=>$usr_id, no_limits=>1};
      $f->{ip}='1.1.1.1';
      # --------------------
      $file = &XUpload::ProcessFile($file,$f) unless $file->{file_status};
      # --------------------
      &Send("Error: $file->{file_status}") if $file->{file_status};

      $cx++;
   }
   &Send("OK:$cx");
}

sub Test
{
   my @tests;
   # Try to CHMOD first
   chmod 0777, $c->{temp_dir};
   chmod 0777, $c->{upload_dir};
   chmod 0777, $c->{htdocs_dir};
   chmod 0755, 'upload.cgi';
   chmod 0755, 'upload_status.cgi';
   chmod 0666, 'XFSConfig.pm';
   chmod 0666, 'logs.txt';

   # temp dir
   push @tests, -d $c->{temp_dir} ? 'temp dir exist: OK' : "temp dir exist: ERROR($!)";
   push @tests, mkdir("$c->{temp_dir}/test") ? 'temp dir mkdir: OK' : "temp dir mkdir: ERROR($!)";
   push @tests, rmdir("$c->{temp_dir}/test") ? 'temp dir rmdir: OK' : "temp dir rmdir: ERROR($!)";
   # url temp dir
   push @tests, -d $c->{htdocs_tmp_dir} ? 'tmp dir exist: OK' : "tmp dir exist: ERROR($!)";
   push @tests, mkdir("$c->{htdocs_tmp_dir}/test") ? 'tmp dir mkdir: OK' : "tmp dir mkdir: ERROR($!)";
   push @tests, rmdir("$c->{htdocs_tmp_dir}/test") ? 'tmp dir rmdir: OK' : "tmp dir rmdir: ERROR($!)";
   # upload dir
   push @tests, -d $c->{upload_dir} ? 'upload dir exist: OK' : "upload dir exist: ERROR($!)";
   push @tests, mkdir("$c->{upload_dir}/test") ? 'upload dir mkdir: OK' : "upload dir mkdir: ERROR($!)";
   push @tests, rmdir("$c->{upload_dir}/test") ? 'upload dir rmdir: OK' : "upload dir rmdir: ERROR($!)";
   # htdocs dir
   push @tests, -d $c->{htdocs_dir} ? 'htdocs dir exist: OK' : "htdocs dir exist: ERROR($!)";
   push @tests, mkdir("$c->{htdocs_dir}/test") ? 'htdocs dir mkdir: OK' : "htdocs dir mkdir: ERROR($!)";
   push @tests, symlink("upload.cgi","$c->{htdocs_dir}/test/test.avi") ? 'htdocs dir symlink: OK' : "htdocs dir symlink: ERROR($!)";
   push @tests, unlink("$c->{htdocs_dir}/test/test.avi") ? 'htdocs dir symlink del: OK' : "htdocs dir symlink del: ERROR($!)";
   push @tests, rmdir("$c->{htdocs_dir}/test") ? 'htdocs dir rmdir: OK' : "htdocs dir rmdir: ERROR($!)";
   # XFSConfig.pm
   push @tests, open(F,'XFSConfig.pm') ? 'config read: OK' : "config read: ERROR($!)";

   if($f->{video_test})
   {
      my $x = `mplayer`;
      push @tests, $x=~/options/is ? 'mplayer: OK' : 'mplayer: ERROR';

      my $x = `$c->{ffmpeg} 2>&1`;
      push @tests, $x=~/version/is ? 'ffmpeg: OK' : 'ffmpeg: ERROR';

      if($c->{mp4box_path})
      {
          my $mp4 = $c->{mp4box_path}||'MP4Box';
          my $x = `$mp4`;
          push @tests, $x=~/option/is ? 'MP4Box: OK' : 'MP4Box: ERROR';
      }
   }

   if($f->{torrent_test})
   {
      push @tests, -e "$c->{cgi_dir}/Torrents/bitflu.pl" ? 'bitflu: OK' : 'bitflu: ERROR';
      eval { require Digest::SHA };
      push @tests, !$@ ? 'Digest::SHA: OK' : 'Digest::SHA: ERROR';
   }

   push @tests, open(F,'>>XFSConfig.pm') ? 'config write: OK' : "config write: ERROR($!)";

   my $site_cgi = $f->{site_cgi};
   my $ua = LWP::UserAgent->new(agent => "XFS-FSAgent",timeout => 90);
   my $res = $ua->post("$site_cgi/fs.cgi",
                       {
                          op => 'test'
                       }
                      );
   push @tests, $res->content =~ /^OK/ ? 'fs.cgi: OK' : 'fs.cgi: ERROR '.$res->content;
   my ($ip) = $res->content =~ /^OK:(.*)/;
   
   &Send( "OK:$ip:".join('|',@tests) );
}

sub UpdateConfig
{
   my $str = $f->{data};
   my $cc;
   for(split(/\~/,$str))
   {
      /^(.+?):(.*)$/;
      $cc->{$1}=$2;
   }

   my $conf;
   open(F,"$c->{cgi_dir}/XFSConfig.pm")||&Send("Can't read Config: $!");
   $conf.=$_ while <F>;
   close F;

   for my $x (keys %{$cc})
   {
      my $val = $cc->{$x};
      
      unless(exists($c->{$x}))
      {
         $conf =~ s/};/ $x => '$val',\n};/
      }

      $conf=~s/$x\s*=>\s*('.*')\s*,/"$x => '$val',"/e;
   }

   open(F,">>$c->{temp_dir}/XFSConfig.pm")||&Send("Can't write Config: $!");
   print F $conf;
   close F;

   move("$c->{temp_dir}/XFSConfig.pm", "$c->{cgi_dir}/XFSConfig.pm") || die("Can't move Config: $!");

   $conf='';
   open(F,"$c->{htdocs_dir}/.htaccess");
   $conf.=$_ while <F>;
   close F;
   $conf=~s/ErrorDocument 404 .+/"ErrorDocument 404 $cc->{site_url}\/404.html"/e;
   open(F,">$c->{htdocs_dir}/.htaccess");
   print F $conf;
   close F;

   &Send('OK');
}

sub CompileChunks
{
   my $fname = $f->{fname};
   my ($sid) = $f->{sid} =~ /(\w+)/;
   my $sess_id = $f->{session_id};

   &SendXML("<Error>Upload session expired</Error>") unless -e "$c->{temp_dir}/$sid";
   &SendXML("<Error>Filename not specified</Error>") unless $fname;
   my $cx=0;
   open(F, ">$c->{temp_dir}/$sid/result") || &SendXML("<Error>Can't create result file</Error>");
   my $buf;
   $|++;
   print"Content-type:text/html\n\n";
   while(-f "$c->{temp_dir}/$sid/file_$cx")
   {
      open(my $fh,"$c->{temp_dir}/$sid/file_$cx") || &SendXML("<Error>Can't open chunk</Error>");
      print F $buf while read($fh, $buf, 4096);
      close $fh;
      unlink("$c->{temp_dir}/$sid/file_$cx");
      $cx++;
      print"\#\n";
   }
   close F;
   print("<Error>No chunks were found</Error>"),exit unless $cx;

   my $file;
   $file->{file_tmp} = "$c->{temp_dir}/$sid/result";
   $file->{file_name_orig} = $fname;
   $f->{compile} = 1; # Dump download and delete link
   $f->{sess_id} = $sess_id;
   $file = &XUpload::ProcessFile($file,$f);

   print("<Error>".$file->{msg}."</Error>"),exit unless $file->{msg}=~/^OK/;
   my ($link,$del_link) = $file->{msg}=~/^OK=(.+?)\|(.+)$/;
   print("<Error>Can't generate link</Error>"),exit unless $link;
   my $dx = sprintf("%05d",$file->{file_id}/$c->{files_per_folder});
   print("<Links><Link>$link</Link>\n<DelLink>$del_link</DelLink></Links>");
   exit;
}

sub TorrentDelete
{
   require TorrentClient;
   print "Content-type: text/html\n\n";
   print TorrentClient->new()->del_torrent(fs_key => $c->{fs_key}, hash => $f->{sid});
   exit;
}

sub TorrentKill
{
   system("kill -9 `cat Torrents/torrent.pid`");
   print"Content-type:text/html\n\nOK";
   exit;
}

sub TorrentStatus
{
   require TorrentClient;
   print"Content-type:text/html\n\n";
   print eval { TorrentClient->new->get_status() } ? 'ON' : '';
   exit;
}

sub TorrentDone
{
	my @files;
   my $sid = $1 if $f->{sid} =~ /^([a-z0-9]+)$/;
   die("No sid") if !$sid;
   XUpload::ImportDir("Torrents/workdir/$sid/", %$f);
   #rmtree("Torrents/workdir/$sid/");
   print "Content-type: text/html\n\nOK";
   exit;
}

sub StartSeeding
{
   require TorrentClient;
   my $tc = TorrentClient->new(rpc_url => "http://127.0.0.1:9092");
   my $dx = sprintf("%05d",($f->{file_real_id}||$f->{file_id})/$c->{files_per_folder});
   my $metainfo = $tc->startseeding(fs_key => $c->{fs_key},
      virtpath => $f->{file_name},
      realpath => "$c->{upload_dir}/$dx/$f->{file_real}");
   print "Content-type: application/x-bittorrent\n\n$metainfo";
   exit;
}

sub Reencode
{
   require XUpload;
   open(FILE,">>$c->{cgi_dir}/enc.list");
   print FILE "$f->{list}\n";
   close FILE;
   print "Content-type: text/html\n\nOK";
   exit;
}

sub Rethumb
{
   require XUpload;
   my $idir = $c->{htdocs_dir};
   $idir=~s/^(.+)\/.+$/$1\/i/;

   my @files = split(/\n/, $f->{list});
   my @file_names = split(/\n/, $f->{file_names});

   for(my $i = 0; $i < @files; $i++)
   {
      @_ = split(/:/, $files[$i]);

      my $file = "$c->{upload_dir}/$_[0]/$_[1]";
      my $ext = lc($1) if $file_names[$i] =~ /\.(\w+)$/;
      symlink($file, "$idir/$_[0]/$_[1].$ext") if $c->{m_i_hotlink_orig};

      XUpload::ResizeImg($file, $c->{m_i_width}, $c->{m_i_height});
      rename("$file\_t.jpg","$idir/$_[0]/$_[1]_t.jpg");
   }
   print "Content-type: text/html\n\nOK";
   exit;
}

sub rarPasswordChange
{
  require XUpload;
  require File::Temp;
  my $dx = sprintf("%05d",$f->{file_id}/$c->{files_per_folder});
  my $file_code = $f->{file_code};
  my $tempdir = File::Temp::tempdir(CLEANUP => 1, DIR => $c->{temp_dir});

  local *chain0 = sub { for(@_) { last if $_->() != 0; } };
  &withSupressOutput(sub {
	  chain0(
	   sub { system("rar", "x", "-ow", "$c->{upload_dir}/$dx/$file_code", $tempdir, "-p$f->{rar_pass}") },
	   sub { system("rar", "a", "-ow", "$c->{upload_dir}/$dx/$file_code.rar", "-ep1", "$tempdir/"); },
	   sub { rename("$c->{upload_dir}/$dx/$file_code.rar", "$c->{upload_dir}/$dx/$file_code"); },
	  );
  });

  my $file_spec = &XUpload::rarGetInfo("$c->{upload_dir}/$dx/$file_code", file_name_orig => $f->{file_name});
  &Send($file_spec);
}

sub rarGetBaggageOpts {
  my ($f) = @_;
  my @ret;

  my $dx = sprintf("%05d",$f->{file_id}/$c->{files_per_folder});
  my $file_path = "$c->{upload_dir}/$dx/$f->{file_code}";

  push @ret, "-p$f->{rar_pass}" if $f->{rar_pass};
  push @ret, $file_path;
  push @ret, @{ JSON::decode_json($f->{files}) } if $f->{files};
  return(@ret);
}

sub getFilePath {
  my ($f) = @_;
  my $dx = sprintf("%05d",$f->{file_id}/$c->{files_per_folder});
  return("$c->{upload_dir}/$dx/$f->{file_code}");
}

sub withSupressOutput
{
   my ($callback) = @_;
   open OLDOUT, '>&STDOUT';
   open STDOUT, '>/dev/null' || die("Couldn't open STDOUT");
   &$callback();
   close STDOUT;
   open STDOUT, '>&OLDOUT';
}

sub withTempDirectory
{
    my (%opts, $callback);
    while($_ = shift) {
        $opts{$_} = shift if !ref($_);
        $callback = $_ if ref($_) eq 'CODE';
    }

    die("callback required") if !$callback;
    my $tmp_dir = tempdir( DIR => $c->{temp_dir}, CLEANUP => 1 );

    # Navigate to empty temp dir
    my $cwd = getcwd();
    chdir($tmp_dir);

    &withSupressOutput(sub {
      &$callback();
    });

    # Collect produced files
    chdir($cwd);
    my @files;
    $opts{glob} ||= '*';
    for(<$tmp_dir/$opts{glob}>) {
        my $file = {
                 file_tmp        => $_, 
                 file_name_orig  => basename($_), 
                 file_public     => 1, 
                };
        push @files, $file;
        XUpload::ProcessFile($file, $f) if $opts{onfinish} eq 'ProcessFile';
    }
    return(@files);
}

sub rarProcess
{
  # Common handler for rar_extract, rar_split, rar_files_delete and rar_password_change
  my @baggage_opts;
  my $ext = lc($1) if $f->{file_name} =~ /\.(zip|rar|7z)/;
  die("Error: Unknown archive type: $f->{file_name}") if !$ext;
  my $prog = $ext eq 'rar' ? 'rar' : '7za';
  my $dx = sprintf("%05d",$f->{file_id}/$c->{files_per_folder});
  my $file_path = "$c->{upload_dir}/$dx/$f->{file_code}";
  push @baggage_opts, "-p$f->{rar_pass}" if $f->{rar_pass};
  push @baggage_opts, "$file_path";
  push @baggage_opts, @{ JSON::decode_json($f->{files}) } if $f->{files};

  my $glob = "*.part*.$ext" if $f->{op} eq 'rar_split' && $prog eq 'rar';
  $glob = "*.part.$ext.*" if $f->{op} eq 'rar_split' && $prog eq '7za';
  &withTempDirectory(glob => $glob,
                     onfinish => 'ProcessFile',
                     sub {
	                     system($prog, 'd', @baggage_opts), return
                            if $f->{op} eq 'rar_file_del';
	                     system($prog, 'e', @baggage_opts);
	                     system($prog, 'a', "-v$f->{part_size}", "$f->{file_name}.part.$ext", '.')
                            if $f->{op} eq 'rar_split';
                     });

  &Send(&XUpload::rarGetInfo($file_path, file_name_orig => $f->{file_name}))
    if $f->{op} eq 'rar_file_del';
  &Send("OK");
}

sub randchar
{ 
   my @range = ('0'..'9','a'..'z');
   my $x = int scalar @range;
   join '', map $range[rand $x], 1..shift||1;
}

sub daemonize
{
    #chdir '/'                 or die "Can't chdir to /: $!";
    #close STDIN               or die "Can't close STDIN: $!";
    defined( my $pid = fork ) or die "Can't fork: $!";
    print("Content-type:text/html\n\nOK"),exit if $pid;
    #setsid                    or die "Can't start a new session: $!";
    close STDOUT              or die "Can't close STDOUT: $!";
    $SIG{CHLD} = 'IGNORE';
}

