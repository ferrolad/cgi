#!/usr/bin/perl
use XFSConfig;
use HCE_MD5;
use CGI::Carp qw(fatalsToBrowser);

$SIG{PIPE} = sub {
    # Not defined implicitly on some systems
    $0 = "dl.cgi SIGPIPE";
    exit(-1);
};

my $code = (split('/',$ENV{REQUEST_URI}))[-2];

my $hce = HCE_MD5->new($c->{dl_key},"XFileSharingPRO");
my ($file_id,$file_code,$speed,$ip1,$ip2,$ip3,$ip4,$expire) = unpack("LA12SC4L", $hce->hce_block_decrypt(decode($code)) );
print("Content-type:text/html\n\nLink expired"),exit if time > $expire;
$speed||=50000;
my $dx = sprintf("%05d",$file_id/$c->{files_per_folder});
my $ip="$ip1.$ip2.$ip3.$ip4";
$ip=~s/\.0$/.\\d+/;
$ip=~s/\.0\./.\\d+./;
$ip=~s/\.0\./.\\d+./;
$ip=~s/^0\./\\d+./;
print("Content-type:text/html\n\nNo file"),exit unless -f "$c->{upload_dir}/$dx/$file_code";
print("Content-type:text/html\n\nWrong IP"),exit if $ip ne '0.0.0.0' && $ip && $ENV{REMOTE_ADDR}!~/^$ip/;
my $fsize = -s "$c->{upload_dir}/$dx/$file_code";
$|++;
open(my $in_fh,"$c->{upload_dir}/$dx/$file_code") || die"Can't open source file";

# unless($ENV{HTTP_ACCEPT_CHARSET}=~/utf-8/i)
# {
#    $fname =~ s/([^A-Za-z0-9\-_.!~*'() ])/ uc sprintf "%%%02x",ord $1 /eg;
#    $fname =~ tr/ /+/;
# }
print qq{Content-Type: application/octet-stream\n};
print qq{Content-length: $fsize\n};
#print qq{Content-Disposition: attachment; filename="$fname"\n};
print qq{Content-Disposition: attachment\n};
print qq{Content-Transfer-Encoding: binary\n\n};


$speed = int 1024*$speed/10;
my $buf;
while( read($in_fh, $buf, $speed) )
{
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
