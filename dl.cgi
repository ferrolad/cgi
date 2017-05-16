#!/usr/bin/perl
use strict;
use XFSConfig;
use HCE_MD5;
use CGI::Carp qw(fatalsToBrowser);
use List::Util qw(min);
use Log;

Log->new(filename => 'dl.log');

$SIG{PIPE} = sub {
    # Not defined implicitly on some systems
    $0 = "dl.cgi SIGPIPE";
    exit(-1);
};

my $code = (split('/',$ENV{REQUEST_URI}))[-2];

my $hce = HCE_MD5->new($c->{dl_key},"XFileSharingPRO");
my ($file_id,$file_code,$speed,$i1,$i2,$i3,$i4,$expire,$m1,$m2,$m3,$m4,$orig,$accept_ranges) = unpack("LA12SC4LC4SS", $hce->hce_block_decrypt(decode($code)) );

print("Content-type:text/html\n\nLink expired"),exit if time > $expire;
print STDERR "GET $file_code from $ENV{REMOTE_ADDR}\n";
$speed||=50000;
my $dx = sprintf("%05d",$file_id/$c->{files_per_folder});

my $expected_ip = join('.', $i1, $i2, $i3, $i4);
my $mask = join('.', $m1, $m2, $m3, $m4);

my $orig_dir = "$1/orig" if $c->{upload_dir} =~ /^(.*)\/uploads/;
my $file_path = $orig ? "$orig_dir/$dx/$file_code" : "$c->{upload_dir}/$dx/$file_code";

print("Content-type:text/html\n\nNo file"),exit unless -f $file_path;
print("Content-type:text/html\n\nWrong IP"),exit if ip_masked($expected_ip, $mask) ne ip_masked($ENV{REMOTE_ADDR}, $mask);

my $fsize = -s $file_path;
$|++;

my ($range_start, $range_end) = split(/-/, $1) if $ENV{HTTP_RANGE} =~ /^bytes=(.*)/;
$range_end ||= $fsize - 1;

my ($start, $end) = ($range_start || $range_end)  ? ($range_start, $range_end + 1) : (0, $fsize);
$end = $fsize if $end > $fsize;
my $content_length = $end - $start;

open(my $in_fh,$file_path) || die"Can't open source file";

if($ENV{HTTP_RANGE} && $accept_ranges)
{
   # Ranges support is a requirement for implementing BEP-19 (client-side webseed)
   print "Status: 206\n";
   print "Content-Range: bytes $range_start-$range_end/$fsize\n";
}

print qq{Content-Type: application/octet-stream\n};
print qq{Content-length: $content_length\n};
#print qq{Content-Disposition: attachment; filename="$fname"\n};
print qq{Content-Disposition: attachment\n};
print qq{Content-Transfer-Encoding: binary\n\n};

my $buf;
my $chunk_size = int 1024*$speed/10;

for(my $pos = $start; $pos < $end; $pos += $chunk_size)
{
   seek($in_fh, $pos, 0);
   read($in_fh, $buf, min($end - $pos, $chunk_size));
   print $buf;
   select(undef,undef,undef,0.1);
}

sub decode
{
   $_ = shift;
   my( $l );
   tr|a-z2-7|\0-\37|;
   $_=unpack('B*', $_);
   s/000(.....)/$1/g;
   $l=length;
   $_=substr($_, 0, $l & ~7) if $l & 7;
   $_=pack('B*', $_);
}

sub ip_masked
{
   my @ip = split(/\./, shift);
   my @mask = split(/\./, shift);
   my @ret = map { int($ip[$_]) & int($mask[$_]) } (0..3);
   join('.', @ret);
}
