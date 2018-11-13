package XUpload;

use strict;
use lib '.';
use XFSConfig;
use Digest::MD5;
use LWP::UserAgent;
use File::Copy;
use Exporter;
use Encode;
use JSON;
use IPC::Open3;

use Fcntl ':mode';
use File::Find;
use File::Basename;

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

@XUpload::ISA = qw(Exporter);
@XUpload::EXPORT = qw(Send SendXML SendJSON);

sub ImportDir
{
   my ($path, %opts) = @_;

   $path =~ s/\/+$//;

   die("No path") if !$path;
   die("Wrong path") if $path !~ /(ftp|temp|Torrents)/;

	find({ wanted => \&wanted, no_chdir => 1 }, $path);
	
	sub wanted
	{
	   my @stat = stat($File::Find::name);
	   next if !S_ISREG($stat[2]);
	   my $fld_path = $1 if $File::Find::dir =~ /^\Q$path\E\/(.*)/;
      my $xfile = { file_tmp => $File::Find::name, file_name_orig => basename($File::Find::name) };
      eval { XUpload::ProcessFile($xfile, { ip => '2.2.2.2', fld_path => "$opts{prefix}/$fld_path", %opts }) };
      print STDERR "Error while importing file: $@\n" if $@;
	}
}

sub saferun
{
   my (@args) = @_;
   my $pid = open3(\*WRFH, \*RDFH, \*ERRFH, @args) || die("Couldn't open: $!");
   my $str = join('', <RDFH>);
   my $status = waitpid($pid, 1);
   return $str;
}

# Mandatory args: file_tmp, file_name_orig, file_descr, file_public
# Optional args: usr_id, no_limits
sub ProcessFile
{
   my ($file,$f) = @_;

   $f->{ip}||=$ENV{REMOTE_ADDR};

   unless(-f $file->{file_tmp})
   {
      $file->{file_status}="No file on disk ($file->{file_tmp})";
      return $file;
   }

   $file->{file_size} = -s $file->{file_tmp};

   my $ua = LWP::UserAgent->new(agent => "XFS-FSAgent", timeout => 90);
   if($c->{enable_clamav_virus_scan})
   {
      my $clam = &saferun("clamscan", "--no-summary", $file->{file_tmp});
      if($clam=~/: (.+?) FOUND/)
      {
         $file->{file_status}="file contain $1 virus";
         return $file;
      }
   }

   if($file->{file_name_orig}=~/\.torrent$/i && $f->{torr_on})
   {
      require TorrentClient;
      my $t = TorrentClient->new;
      my $tt = $t->startdl(metainfo => [ $file->{file_tmp} ]);
      print"Content-type:text/html\n\n";
      print"<HTML><HEAD><Script type='text/javascript'>top.location='$c->{site_url}/?op=my_files';</Script></HEAD></HTML>";
      exit;
   }

   open(FILE,$file->{file_tmp})||die"cant open file";
   my $data;
   read(FILE,$data,4096);
   seek(FILE,-4096,2);
   read(FILE,$data,4096,4096);
   $file->{md5} = Digest::MD5::md5_base64 $data;

   if($c->{m_v} && $file->{file_name_orig}=~/\.(avi|divx|xvid|mpg|mpeg|vob|mov|3gp|flv|mp4|wmv|mkv)$/i)
   {
      my $info = &saferun("./mplayer", $file->{file_tmp}, "-identify", "-frames", "0", "-quiet", "-ao", "null", "-vo", "null");
      my @fields = qw(ID_LENGTH ID_VIDEO_WIDTH ID_VIDEO_HEIGHT ID_VIDEO_BITRATE ID_AUDIO_BITRATE ID_AUDIO_RATE ID_VIDEO_CODEC ID_AUDIO_CODEC ID_VIDEO_FPS);
      do{($f->{$_})=$info=~/$_=([\w\.]{2,})/is} for @fields;
      $f->{ID_LENGTH} = int $f->{ID_LENGTH};
      if($f->{ID_VIDEO_WIDTH})
      {
         $f->{ID_VIDEO_BITRATE}=int($f->{ID_VIDEO_BITRATE}/1000);
         $f->{ID_AUDIO_BITRATE}=int($f->{ID_AUDIO_BITRATE}/1000);
         $file->{file_spec} = 'V|'.join('|', map{$f->{$_}}@fields );
      }
   }

   if($file->{file_name_orig}=~/\.mp3$/i)
   {
      $file->{type}='audio';
      require MP3::Info;
      my $info = MP3::Info::get_mp3info($file->{file_tmp});
      if($info)
      {
         my $tag = MP3::Info::get_mp3tag($file->{file_tmp},1);
         $tag->{$_}=encode_utf8($tag->{$_}) for keys %$tag;
         $tag->{$_}=~s/\|//g for keys %$tag;
         $info->{SECS} = sprintf("%.1f", $info->{SECS} );
         $file->{file_spec}="A|$info->{SECS}|$info->{BITRATE}|$info->{FREQUENCY}|$tag->{ARTIST}|$tag->{TITLE}|$tag->{ALBUM}|$tag->{YEAR}";
      }
   }

   if($c->{m_i} && $file->{file_name_orig}=~/\.(jpg|jpeg|gif|png|bmp)$/i)
   {
      $file->{type}='image';
   }

   if($file->{file_name_orig}=~/\.(rar|zip|7z)$/i && $c->{m_b})
   {
      $file->{file_spec} = &rarGetInfo( $file->{file_tmp}, file_name_orig => $file->{file_name_orig} );
   }

   ##### LWP
   my $res = $ua->post("$c->{site_cgi}/fs.cgi",
                       {
                       fs_key       => $c->{fs_key},
                       file_name    => $file->{file_name_orig},
                       file_descr   => $file->{file_descr},
                       file_size    => $file->{file_size},
                       file_public  => $file->{file_public}||$f->{file_public},
                       file_adult   => $f->{file_adult},
                       rslee        => $file->{rslee},
                       file_md5     => $file->{md5},
                       file_spec    => $file->{file_spec},
                       usr_id       => $file->{usr_id}||$f->{usr_id},
                       no_limits    => $file->{no_limits},
                       sid          => $file->{sid}||$f->{sid},
                       torrent      => $file->{torrent},
                       sess_id      => $f->{sess_id}||'',
                       file_password=> $f->{link_pass}||'',
                       file_ip      => $f->{ip},
                       fld_id       => $f->{to_folder}||'', # Upload form
                       fld_path     => $f->{fld_path}||'',
                       check_login  => $f->{check_login}||'',
                       check_pass   => $f->{check_pass}||'',
                       compile      => $f->{compile}||'', # Desktop uploader
                       usr_login    => $file->{usr_login}||$f->{usr_login}||'',
                       uploader_id  => $f->{uploader_id}||0,
                       file_upload_method => $f->{file_upload_method}||'',
                       }
                      );
   my $info = $res->content;
   #die $info;
   print STDERR "INFO:$info";
   ($file->{file_id},$file->{file_code},$file->{file_real},$file->{msg}) = $info=~/^(\d+):(\w+):(\w+):(.*)$/;
   $file->{dx} = &getDx($file);

   if($file->{msg} !~ /^OK/)
   {
      $file->{file_status} = $file->{msg} || "failed while requesting fs.cgi: $info";
      return $file;
   }

   if(!$file->{file_code})
   {
      $file->{file_status}="error connecting to DB";
      return $file;
   }

   &SaveFile( $file ) if $file->{file_code} eq $file->{file_real};

   if($file->{new_size})
   {
      my $res = $ua->post("$c->{site_cgi}/fs.cgi",
                       {
                       fs_key    => $c->{fs_key},
                       op        => 'file_new_size',
                       file_code => $file->{file_code},
                       file_size => $file->{file_size},
                       file_name => $file->{file_name_orig},
                       }
                      );
   }
   return $file;
}

sub parseRar {
   my @stdout = @_;
   my (@parsed_data, $start, $pass, $comment);

   for(@stdout) {
      chomp;
      $comment = $1 if /^Comment: (.*)/;
      $start++, next if /^-{3}/;
      $pass=1 if $_=~ /^\*/; # Encrypted files
      $pass=1 if $_=~ /password incorrect/; # Encrypted header
      next if $start != 1;
      s/^\s*//;

      my @chunks;
      for my $i ((1..9)) {
         $_ =~ s/\s+(\S+)$//g;
         push @chunks, $1;
      }

      push @parsed_data, {
         file_name => $_,
                   file_size => $chunks[8],
                   directory => $chunks[3] =~ /^d/i ? 1 : 0,
      };
   }

   return { files => \@parsed_data,
      password_protected => $pass,
      comment => $comment,
   };
}

sub parse7zip {
   # Input format:
   # 1) A sequence of three or more hyphens starts the files section
   # 2) Each key / value pair is going to hash
   # 3) Void value commits a new record in @parsed_data
   my @stdout = @_;
   my $info;
   my (@parsed_data, %hash, $start, $pass, $comment);
   for(@stdout) {
      chomp;
      $start = 1 if /^-{3}/;
      next if !$start;

      my ($key, $value) = split(/\s*=\s*/, $_, 2);
      $hash{$key} = $value;

      push @parsed_data, { file_name => $hash{Path},
         file_size => $hash{Size},
         directory => $hash{Attributes} =~ /^d/i ? 1 : 0,
      } if !$_;
   }

   return { files => \@parsed_data,
      password_protected => $pass,
      comment => $comment,
   };
}

sub rarGetInfo
{
   $ENV{LANG} = "en_US.UTF-8";

   my ( $file_tmp, %opts ) = @_;
   my $file_name_orig = $opts{file_name_orig};

   my $spec = &parseRar(`rar -p- l $file_tmp 2>&1`) if $file_name_orig =~ /\.rar$/i;
   $spec = &parse7zip(`7za l -slt $file_tmp`) if ($file_name_orig =~ /\.(zip|7z)$/i);
   print STDERR "Error: Unknown archive type: $file_name_orig" if(!$spec);

   my @rf;
   for(@{$spec->{files}}) {
      $_->{file_size} = $_->{file_size} > 2**20
         ? sprintf("%.1f MB",$_->{file_size}/2**20)
         : sprintf("%.0f KB",$_->{file_size}/2**10);
      push @rf, "$_->{file_name} - $_->{file_size}";
   }

   my $file_spec;
   $file_spec="password protected\n" if $spec->{password_protected};
   $file_spec.=join "\n", @rf;
   $file_spec.="\n\n$spec->{comment}" if $spec->{comment};
   return $file_spec;
}

########

sub SaveFile
{
   my ($file) = @_;
   my $dx = &getDx($file);
   unless(-d "$c->{upload_dir}/$dx")
   {
      my $mode = 0777;
      mkdir("$c->{upload_dir}/$dx",$mode) || do{print STDERR "Fatal Error: Can't copy file from temp dir ($!)";&xmessage("Fatal Error: Can't copy file from temp dir ($!)")};
      chmod $mode,"$c->{upload_dir}/$dx";
   }
   move($file->{file_tmp},"$c->{upload_dir}/$dx/$file->{file_code}") || copy($file->{file_tmp},"$c->{upload_dir}/$dx/$file->{file_code}") || do{print STDERR "Fatal Error: Can't copy file from temp dir ($!)";&xmessage("Fatal Error: Can't copy file from temp dir ($!)")};
   my $mode = 0666;
   chmod $mode,"$c->{upload_dir}/$dx/$file->{file_code}";

   my $idir = $c->{htdocs_dir};
   $idir=~s/^(.+)\/.+$/$1\/i/;
   $mode = 0777;
   mkdir($idir,$mode) unless -d $idir;
   mkdir("$idir/$dx",$mode) unless -d "$idir/$dx";
   chmod $mode,"$idir/$dx";

   if($c->{m_i} && $file->{file_name_orig}=~/\.(jpg|jpeg|gif|png|bmp)$/i)
   {
      my $ext = lc $1;
      &ResizeImg("$c->{upload_dir}/$dx/$file->{file_code}",$c->{m_i_width},$c->{m_i_height});
      rename("$c->{upload_dir}/$dx/$file->{file_code}_t.jpg","$idir/$dx/$file->{file_code}_t.jpg");
      $file->{new_size} = 1;
      if($c->{m_i_wm_image})
      {
         &WatermarkImg("$c->{upload_dir}/$dx/$file->{file_code}");
         $file->{file_size} = -s "$c->{upload_dir}/$dx/$file->{file_code}";
         $file->{file_name_orig}=~s/\.\w+$/\.jpg/;
         #rename("$idir/$dx/$file->{file_code}.$ext","$idir/$dx/$file->{file_code}.jpg") unless $ext eq 'jpg';
         $ext='jpg';
      }
      symlink("$c->{upload_dir}/$dx/$file->{file_code}", "$idir/$dx/$file->{file_code}.$ext") if $c->{m_i_hotlink_orig};
   }
   if($c->{m_v} && $file->{file_spec}=~/^V/)
   {
      $file->{type}='video';
      &saferun("./mplayer", "$c->{upload_dir}/$dx/$file->{file_code}", "-ss", "00:05", "-vo", "jpeg:outdir=$c->{temp_dir}:quality=65", "-nosound", "-frames", "1", "-slave", "-really-quiet", "-nojoystick", "-nolirc", "-nocache", "-noautosub");
      if(-e "$c->{temp_dir}/00000001.jpg")
      {
       move("$c->{temp_dir}/00000001.jpg","$idir/$dx/$file->{file_code}.jpg");
      }
      else
      {
        symlink("$idir/default.jpg","$idir/$dx/$file->{file_code}.jpg");
      }
      &saferun("./mplayer", "$c->{upload_dir}/$dx/$file->{file_code}", "-ss", "00:05", "-vf", "scale=200:-3", "-vo", "jpeg:outdir=$c->{temp_dir}:quality=65", "-nosound", "-frames", "1", "-slave", "-really-quiet", "-nojoystick", "-nolirc", "-nocache", "-noautosub");
      if(-e "$c->{temp_dir}/00000001.jpg")
      {
       move("$c->{temp_dir}/00000001.jpg","$idir/$dx/$file->{file_code}_t.jpg");
      }
      else
      {
        symlink("$idir/default.jpg","$idir/$dx/$file->{file_code}_t.jpg");
      }
   }
   if($c->{m_e} && $file->{file_name_orig}=~/\.(avi|divx|xvid|mpg|mpeg|vob|mov|3gp|flv|mp4|wmv|mkv)$/i)
   {
      open(FILE,">>$c->{cgi_dir}/enc.list");
      print FILE "$dx:$file->{file_code}\n";
      close FILE;
   }
}

sub MD5Hash
{
   my ($file) = @_;
   open(FILE,$file)||die"cant open file";
   my $data;
   read(FILE,$data,4096);
   seek(FILE,-4096,2);
   read(FILE,$data,4096,4096);
   return(Digest::MD5::md5_base64 $data);
}

sub getDx
{
   my ($file) = @_;
   return( sprintf("%05d",$file->{file_id}/$c->{files_per_folder}) );
}

sub ResizeImg
{
   my ($file,$width_max,$height_max) = @_;
   $width_max||=150;
   $height_max||=150;
   if($c->{m_i_magick})
   {
      &resizeMagick($file,$width_max,$height_max);
   }
   else
   {
      &resizeGD($file,$width_max,$height_max);
   }
}

sub resizeGD
{
   my ($file,$width_max,$height_max) = @_;
   eval { require GD; };
   return if $@;
   GD::Image->trueColor(1);
   my $image = GD::Image->new($file);
   return unless $image;
   my ($width,$height) = $image->getBounds();
   my $thumb;
   if($c->{m_i_resize}) # Cropped
   {
      my ($dx,$dy)=(0,0);
      if($width/$height >= $width_max/$height_max) ### Horizontal
      {
         $dx = sprintf("%.0f", ($width-$width_max*$height/$height_max)/2 );
      }
      else
      {
         $dy = sprintf("%.0f", ($height-$height_max*$width/$width_max)/2 );
      }
      $thumb = GD::Image->newTrueColor($width_max,$height_max);
      $thumb->copyResampled($image,0,0,$dx,$dy,$width_max,$height_max,$width-2*$dx,$height-2*$dy);
   }
   else
   {
      $image->transparent($image->colorAllocate(255,255,255));
      my $k_w = $width_max / $width;
      my $k_h = $height_max / $height;
      my $k = ($k_h < $k_w ? $k_h : $k_w);
      my $width1  = int(0.99+$width * $k);
      my $height1 = int(0.99+$height * $k);
      $thumb = GD::Image->new($width1,$height1);
      $thumb->copyResampled($image, 0,0,0,0, $width1, $height1, $width, $height);
   }
   
   my $jpegdata = $thumb->jpeg(70);
   $file=~s/\.(jpg|jpeg|gif|png|bmp)$//i;
   open(FILE,">$file\_t.jpg")||die"can't write th:$!";
   binmode FILE;
   print FILE $jpegdata;
   close(FILE);
}

sub resizeMagick
{
   my ($file,$width_max,$height_max) = @_;
   eval { require Image::Magick; };
   return if $@;
   my $image=Image::Magick->new;
   my $x = $image->Read($file);
   return if $x;
   $image = $image->[0] if $image->[0];
   my ($width,$height) = $image->Get('width', 'height');
   my $thumb;
   if($c->{m_i_resize}) # Cropped
   {
      my ($dx,$dy)=(0,0);
      if($width/$height >= $width_max/$height_max) ### Horizontal
      {
         $dx = sprintf("%.0f", ($width-$width_max*$height/$height_max)/2 );
      }
      else
      {
         $dy = sprintf("%.0f", ($height-$height_max*$width/$width_max)/2 );
      }

      my $w1 = $width-$dx*2;
      my $h1 = $height-$dy*2;
      $image->Crop(geometry=>$w1."x$h1+$dx+$dy");
      $x = $image->Resize( width=>$width_max, height=>$height_max, filter=>'Lanczos');
      die $x if $x;
   }
   else
   {
      my $k_w = $width_max / $width;
      my $k_h = $height_max / $height;
      my $k = ($k_h < $k_w ? $k_h : $k_w);
      my $width1  = int(0.99+$width * $k);
      my $height1 = int(0.99+$height * $k);
      $x = $image->Resize( width=>$width1, height=>$height1, filter=>'Lanczos');
   }
   
   $file=~s/\.(jpg|jpeg|gif|png|bmp)$//i;
   $image->Strip();
   $x = $image->Write( filename => "$file\_t.jpg", quality=>60, compression => 'JPEG');
   die $x if $x;
   undef $image;
}

sub WatermarkImg
{
   my ($file) = @_;
   return unless -f "$c->{cgi_dir}/$c->{m_i_wm_image}";
   eval { require GD; };
   return if $@;
   GD::Image->trueColor(1);
   my $image = GD::Image->new("$file");
   my $mark = GD::Image->new("$c->{cgi_dir}/$c->{m_i_wm_image}");
   return unless $image && $mark;
   my ($x,$y);
   my $dx=$c->{m_i_wm_padding};
   $c->{m_i_wm_position}||='nw';
   if($c->{m_i_wm_position} eq 'nw')
   {
      $x = $dx;
      $y = $dx;
   }
   elsif($c->{m_i_wm_position} eq 'n')
   {
      $x = int ($image->width-$mark->width)/2;
      $y = $dx;
   }
   elsif($c->{m_i_wm_position} eq 'ne')
   {
      $x = $image->width - $mark->width - $dx;
      $y = $dx;
   }
   elsif($c->{m_i_wm_position} eq 'w')
   {
      $x = $dx;
      $y = int ($image->height-$mark->height)/2;
   }
   elsif($c->{m_i_wm_position} eq 'c')
   {
      $x = int ($image->width-$mark->width)/2;
      $y = int ($image->height-$mark->height)/2;
   }
   elsif($c->{m_i_wm_position} eq 'e')
   {
      $x = $image->width - $mark->width - $dx;
      $y = int ($image->height-$mark->height)/2;
   }
   elsif($c->{m_i_wm_position} eq 'sw')
   {
      $x = $dx;
      $y = $image->height - $mark->height - $dx;
   }
   elsif($c->{m_i_wm_position} eq 's')
   {
      $x = int ($image->width-$mark->width)/2;
      $y = $image->height - $mark->height - $dx;
   }
   elsif($c->{m_i_wm_position} eq 'se')
   {
      $x = $image->width - $mark->width - $dx;
      $y = $image->height - $mark->height - $dx;
   }
   $image->copy($mark, $x, $y, 0, 0, $mark->width, $mark->height);
   open(FILE,">$file\_w")||die"can't write img:$!";
   print FILE $image->jpeg(85);
   close(FILE);
   rename("$file\_w",$file) if -f "$file\_w";
   unlink("$file\_w") if -f "$file\_w";
   undef $image;
}

sub xmessage
{
   my ($msg) = @_;
   $msg=~s/'/\\'/g;
   $msg=~s/<br>/\\n/g;
   $msg=~s/\n/\\n/g;
   print"Content-type: text/html\n\n";
   print"<HTML><HEAD><Script>alert('$msg');</Script></HEAD><BODY><b>$msg</b></BODY></HTML>";
   exit;
}

sub Send
{
   print"Content-type:text/html\n\n@_";
   exit;
}

sub SendXML
{
   print"Content-type:text/html\n\n",shift;
   exit;
}

sub SendJSON
{
   print "Content-type:application/json\n\n", JSON::encode_json($_[0]);
   exit;
}

1;
