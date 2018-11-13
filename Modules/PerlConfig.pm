package PerlConfig;
use strict;
use File::Basename;

sub Write
{
   my ($path, $data, %opts) = @_;

   my $config = Read($path);
   my @fields = @{ $opts{fields} } if $opts{fields};
   my $filename = basename($path);

   my $conf;
   open(F, $path)||die("Couldn't read '$filename': $1<br>\nPlease check that the file is readable by user.<br>\n");
   $conf.=$_ while <F>;
   close F;

   for my $key (keys %$data)
   {
      $data->{$key}=~s/\r//gs;
      $data->{$key}=~s/\n/|/gs;
      $data->{$key}=~s/\|{2,99}/|/gs;
      $data->{$key}=~s/\|$//gs;
      
      $data->{$key}=~s/&lt;/</gs;
      $data->{$key}=~s/&gt;/>/gs;
      $data->{$key}=~s/\\/\\\\/g;
      $data->{$key}=~s/'/\\'/g;
   }

   for my $x (@fields)
   {
      my $val = $data->{$x};
      
      unless(exists($config->{$x}))
      {
         $conf =~ s/};/ $x => '$val',\n};/
      }
      
      $conf=~s/$x\s*=>\s*('.*')\s*,/"$x => '$val',"/e;
   }
   
   my $temp_file = $opts{temp_file}||"$path~";
   open(F,">$temp_file")||die("Couldn\'t write '".basename($temp_file)."': $!<br>\nPlease check that directory is writeable by user.<br>\n");
   print F $conf;
   close F;

   my $result = do($temp_file);
   if(ref($result) eq '' && $result)
   {
      rename($temp_file, $path) || die("Couldn't rename $temp_file to $path: $!");
   }
   else
   {
      die("Failed while writing $path: $@");
   }
}

sub Read
{
   my ($path) = @_;

   require "$path";
   my $pkg = $1 if $path =~ /([^\/]+)\.\w+$/;
   my $c = eval("\$$pkg\::c");
   die("Imported config is not a hashref") if ref($c) ne 'HASH';
   
   return $c;
}

1;
