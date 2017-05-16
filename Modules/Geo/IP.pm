package Geo::IP;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT  $GEOIP_PP_ONLY @ISA $XS_VERSION);

BEGIN { $GEOIP_PP_ONLY = 0 unless defined($GEOIP_PP_ONLY); }

BEGIN {
  $VERSION = '1.38';
  eval {

    # PERL_DL_NONLAZY must be false, or any errors in loading will just
    # cause the perl code to be tested
    local $ENV{PERL_DL_NONLAZY} = 0 if $ENV{PERL_DL_NONLAZY};

    require DynaLoader;
    local @ISA = qw(DynaLoader);
    bootstrap Geo::IP $VERSION;
  } unless $GEOIP_PP_ONLY;
}

require Geo::IP::Record;

sub GEOIP_STANDARD()     { 0; }    # PP
sub GEOIP_MEMORY_CACHE() { 1; }    # PP
sub GEOIP_CHECK_CACHE()  { 2; }
sub GEOIP_INDEX_CACHE()  { 4; }
sub GEOIP_MMAP_CACHE()   { 8; }    # PP

sub GEOIP_UNKNOWN_SPEED()   { 0; } #PP
sub GEOIP_DIALUP_SPEED()    { 1; } #PP
sub GEOIP_CABLEDSL_SPEED()  { 2; } #PP
sub GEOIP_CORPORATE_SPEED() { 3; } #PP

BEGIN {

  #my $pp = !( defined &_XScompiled && &_XScompiled && !$TESTING_PERL_ONLY );
  my $pp = !defined &open;

  sub GEOIP_COUNTRY_EDITION()     { 1; }
  sub GEOIP_CITY_EDITION_REV1()   { 2; }
  sub GEOIP_REGION_EDITION_REV1() { 3; }
  sub GEOIP_ISP_EDITION()         { 4; }
  sub GEOIP_ORG_EDITION()         { 5; }
  sub GEOIP_CITY_EDITION_REV0()   { 6; }
  sub GEOIP_REGION_EDITION_REV0() { 7; }
  sub GEOIP_PROXY_EDITION()       { 8; }
  sub GEOIP_ASNUM_EDITION()       { 9; }
  sub GEOIP_NETSPEED_EDITION()    { 10; }
  sub GEOIP_DOMAIN_EDITION()      { 11; }

  sub GEOIP_CHARSET_ISO_8859_1() { 0; }
  sub GEOIP_CHARSET_UTF8()       { 1; }

  # cheat --- try to load Sys::Mmap PurePerl only
  if ($pp) {
    eval "require Sys::Mmap"
      ? Sys::Mmap->import
      : do {
      for (qw/ PROT_READ MAP_PRIVATE MAP_SHARED /) {
        no strict 'refs';
        my $unused_stub = $_;    # we must use a copy
        *$unused_stub = sub { die 'Sys::Mmap required for mmap support' };
      }
      }    # do
  }    # pp

}

eval << '__PP_CODE__' unless defined &open;

use strict;
use FileHandle;
use File::Spec;

BEGIN {
  if ( $] >= 5.008 ) {
    require Encode;
	Encode->import(qw/ decode /);
  }
  else {
    *decode = sub {
      local $_ = $_[1];
      use bytes;
       s/([\x80-\xff])/my $c = ord($1);
	       my $p = $c >= 192 ? 1 : 0; 
	       pack ( 'CC' => 0xc2 + $p , $c & ~0x40 ); /ge;
	   return $_;
    };
  }
};

use vars qw/$PP_OPEN_TYPE_PATH/;

use constant FULL_RECORD_LENGTH        => 50;
use constant GEOIP_COUNTRY_BEGIN       => 16776960;
use constant RECORD_LENGTH             => 3;
use constant GEOIP_STATE_BEGIN_REV0    => 16700000;
use constant GEOIP_STATE_BEGIN_REV1    => 16000000;
use constant STRUCTURE_INFO_MAX_SIZE   => 20;
use constant DATABASE_INFO_MAX_SIZE    => 100;

use constant SEGMENT_RECORD_LENGTH     => 3;
use constant STANDARD_RECORD_LENGTH    => 3;
use constant ORG_RECORD_LENGTH         => 4;
use constant MAX_RECORD_LENGTH         => 4;
use constant MAX_ORG_RECORD_LENGTH     => 300;
use constant US_OFFSET                 => 1;
use constant CANADA_OFFSET             => 677;
use constant WORLD_OFFSET              => 1353;
use constant FIPS_RANGE                => 360;

my @continents = qw/
--
AS EU EU AS AS SA SA EU AS SA
AF AN SA OC EU OC SA AS EU SA
AS EU AF EU AS AF AF SA AS SA
SA SA AS AF AF EU SA NA AS AF
AF AF EU AF OC SA AF AS SA SA
SA AF AS AS EU EU AF EU SA SA
AF SA EU AF AF AF EU AF EU OC
SA OC EU EU EU AF EU SA AS SA
AF EU SA AF AF SA AF EU SA SA
OC AF SA AS AF SA EU SA EU AS
EU AS AS AS AS AS EU EU SA AS
AS AF AS AS OC AF SA AS AS AS
SA AS AS AS SA EU AS AF AF EU
EU EU AF AF EU EU AF OC EU AF
AS AS AS OC SA AF SA EU AF AS
AF NA AS AF AF OC AF OC AF SA
EU EU AS OC OC OC AS SA SA OC
OC AS AS EU SA OC SA AS EU OC
SA AS AF EU AS AF AS OC AF AF
EU AS AF EU EU EU AF EU AF AF
SA AF SA AS AF SA AF AF AF AS
AS OC AS AF OC AS AS SA OC AS
AF EU AF OC NA SA AS EU SA SA
SA SA AS OC OC OC AS AF EU AF
AF EU AF -- -- -- EU EU EU EU
SA SA
/;

my @countries = (
  undef, qw/
 AP EU AD AE AF AG AI 
 AL AM AN AO AQ AR AS AT 
 AU AW AZ BA BB BD BE BF 
 BG BH BI BJ BM BN BO BR 
 BS BT BV BW BY BZ CA CC 
 CD CF CG CH CI CK CL CM 
 CN CO CR CU CV CX CY CZ 
 DE DJ DK DM DO DZ EC EE 
 EG EH ER ES ET FI FJ FK 
 FM FO FR FX GA GB GD GE 
 GF GH GI GL GM GN GP GQ 
 GR GS GT GU GW GY HK HM 
 HN HR HT HU ID IE IL IN 
 IO IQ IR IS IT JM JO JP 
 KE KG KH KI KM KN KP KR 
 KW KY KZ LA LB LC LI LK 
 LR LS LT LU LV LY MA MC 
 MD MG MH MK ML MM MN MO 
 MP MQ MR MS MT MU MV MW 
 MX MY MZ NA NC NE NF NG 
 NI NL NO NP NR NU NZ OM 
 PA PE PF PG PH PK PL PM 
 PN PR PS PT PW PY QA RE 
 RO RU RW SA SB SC SD SE 
 SG SH SI SJ SK SL SM SN 
 SO SR ST SV SY SZ TC TD 
 TF TG TH TJ TK TM TN TO 
 TL TR TT TV TW TZ UA UG 
 UM US UY UZ VA VC VE VG 
 VI VN VU WF WS YE YT RS 
 ZA ZM ME ZW A1 A2 O1 AX 
 GG IM JE BL MF/
);
my @code3s = ( undef, qw/
                   AP  EU  AND ARE AFG ATG AIA
               ALB ARM ANT AGO AQ  ARG ASM AUT
               AUS ABW AZE BIH BRB BGD BEL BFA
               BGR BHR BDI BEN BMU BRN BOL BRA
               BHS BTN BV  BWA BLR BLZ CAN CC
               COD CAF COG CHE CIV COK CHL CMR
               CHN COL CRI CUB CPV CX  CYP CZE
               DEU DJI DNK DMA DOM DZA ECU EST
               EGY ESH ERI ESP ETH FIN FJI FLK
               FSM FRO FRA FX  GAB GBR GRD GEO
               GUF GHA GIB GRL GMB GIN GLP GNQ
               GRC GS  GTM GUM GNB GUY HKG HM
               HND HRV HTI HUN IDN IRL ISR IND
               IO  IRQ IRN ISL ITA JAM JOR JPN
               KEN KGZ KHM KIR COM KNA PRK KOR
               KWT CYM KAZ LAO LBN LCA LIE LKA
               LBR LSO LTU LUX LVA LBY MAR MCO
               MDA MDG MHL MKD MLI MMR MNG MAC
               MNP MTQ MRT MSR MLT MUS MDV MWI
               MEX MYS MOZ NAM NCL NER NFK NGA
               NIC NLD NOR NPL NRU NIU NZL OMN
               PAN PER PYF PNG PHL PAK POL SPM
               PCN PRI PSE PRT PLW PRY QAT REU
               ROU RUS RWA SAU SLB SYC SDN SWE
               SGP SHN SVN SJM SVK SLE SMR SEN
               SOM SUR STP SLV SYR SWZ TCA TCD
               TF  TGO THA TJK TKL TKM TUN TON
               TLS TUR TTO TUV TWN TZA UKR UGA
               UM  USA URY UZB VAT VCT VEN VGB
               VIR VNM VUT WLF WSM YEM YT  SRB
               ZAF ZMB MNE ZWE A1  A2  O1  ALA
			   GGY IMN JEY BLM MAF         /
);

sub open {
  die "Geo::IP::open() requires a path name"
    unless ( @_ > 1 and $_[1] );
  my ( $class, $db_file, $flags ) = @_;
  my $fh = FileHandle->new;
  my $gi;
  CORE::open $fh, "$db_file" or die "Error opening $db_file";
  binmode($fh);
  if ( $flags && ( $flags & ( GEOIP_MEMORY_CACHE | GEOIP_MMAP_CACHE ) ) ) {
    my %self;
 		if ( $flags & GEOIP_MMAP_CACHE ) {
		  die "Sys::Mmap required for MMAP support"
		    unless defined $Sys::Mmap::VERSION;
		  mmap( $self{buf} = undef, 0, PROT_READ, MAP_PRIVATE, $fh )
		    or die "mmap: $!";
		}
    else {
		  local $/ = undef;
		  $self{buf} = <$fh>;
		}   
		$self{fh}  = $fh;
    $gi = bless \%self, $class;
  }
	else {
	  $gi = bless { fh => $fh }, $class;
	}
	$gi->_setup_segments();
	return $gi;
}

sub new {
  my ( $class, $db_file, $flags ) = @_;

  # this will be less messy once deprecated new( $path, [$flags] )
  # is no longer supported (that's what open() is for)
  my $def_db_file = '/usr/local/share/GeoIP/GeoIP.dat';
  if ($^O eq 'NetWare') {
    $def_db_file = 'sys:/etc/GeoIP/GeoIP.dat';
  } elsif ($^O eq 'MSWin32') {
    $def_db_file = 'c:/GeoIP/GeoIP.dat';
  }
  if ( !defined $db_file ) {

    # called as new()
    $db_file = $def_db_file;
  }
  elsif ( $db_file =~ /^\d+$/	) {
    # called as new( $flags )
    $flags   = $db_file;
    $db_file = $def_db_file;
  }    # else called as new( $database_filename, [$flags] );

  $class->open( $db_file, $flags );
}

#this function setups the database segments
sub _setup_segments {
  my ($gi) = @_;
  my $a    = 0;
  my $i    = 0;
  my $j    = 0;
  my $delim;
  my $buf;

  $gi->{_charset} = GEOIP_CHARSET_ISO_8859_1; 
  $gi->{"databaseType"}  = GEOIP_COUNTRY_EDITION;
  $gi->{"record_length"} = STANDARD_RECORD_LENGTH;

  my $filepos = tell( $gi->{fh} );
  seek( $gi->{fh}, -3, 2 );
  for ( $i = 0; $i < STRUCTURE_INFO_MAX_SIZE; $i++ ) {
    read( $gi->{fh}, $delim, 3 );

    #find the delim
    if ( $delim eq ( chr(255) . chr(255) . chr(255) ) ) {
      read( $gi->{fh}, $a, 1 );

      #read the databasetype
      my $database_type = ord($a);

      # backward compatibility for 2003 databases.
      $database_type -= 105 if $database_type >= 106;
      $gi->{"databaseType"} = $database_type;

#chose the database segment for the database type
#if database Type is GEOIP_REGION_EDITION then use database segment GEOIP_STATE_BEGIN
      if ( $gi->{"databaseType"} == GEOIP_REGION_EDITION_REV0 ) {
        $gi->{"databaseSegments"} = GEOIP_STATE_BEGIN_REV0;
      }
      elsif ( $gi->{"databaseType"} == GEOIP_REGION_EDITION_REV1 ) {
        $gi->{"databaseSegments"} = GEOIP_STATE_BEGIN_REV1;
      }

#if database Type is GEOIP_CITY_EDITION, GEOIP_ISP_EDITION or GEOIP_ORG_EDITION then
#read in the database segment
      elsif (    ( $gi->{"databaseType"} == GEOIP_CITY_EDITION_REV0 )
              || ( $gi->{"databaseType"} == GEOIP_CITY_EDITION_REV1 )
              || ( $gi->{"databaseType"} == GEOIP_ORG_EDITION )
              || ( $gi->{"databaseType"} == GEOIP_DOMAIN_EDITION )
              || ( $gi->{"databaseType"} == GEOIP_ISP_EDITION ) ) {
        $gi->{"databaseSegments"} = 0;

        #read in the database segment for the database type
        read( $gi->{fh}, $buf, SEGMENT_RECORD_LENGTH );
        for ( $j = 0; $j < SEGMENT_RECORD_LENGTH; $j++ ) {
          $gi->{"databaseSegments"} +=
            ( ord( substr( $buf, $j, 1 ) ) << ( $j * 8 ) );
        }

#record length is four for ISP databases and ORG databases
#record length is three for country databases, region database and city databases
        if (    $gi->{"databaseType"} == GEOIP_ORG_EDITION 
             || $gi->{"databaseType"} == GEOIP_ISP_EDITION
             || $gi->{"databaseType"} == GEOIP_DOMAIN_EDITION ){
          $gi->{"record_length"} = ORG_RECORD_LENGTH;
        }
      }
      last;
    }
    else {
      seek( $gi->{fh}, -4, 1 );
    }
  }

#if database Type is GEOIP_COUNTY_EDITION then use database segment GEOIP_COUNTRY_BEGIN
  if (    $gi->{"databaseType"} == GEOIP_COUNTRY_EDITION
       || $gi->{"databaseType"} == GEOIP_NETSPEED_EDITION ) {
    $gi->{"databaseSegments"} = GEOIP_COUNTRY_BEGIN;
  }
  seek( $gi->{fh}, $filepos, 0 );
  return $gi;
}

sub _seek_country {
  my ( $gi, $ipnum ) = @_;

  my $fh     = $gi->{fh};
  my $offset = 0;

  my ( $x0, $x1 );

  my $reclen = $gi->{record_length};

  for ( my $depth = 31; $depth >= 0; $depth-- ) {
    unless ( exists $gi->{buf} ) {
      seek $fh, $offset * 2 * $reclen, 0;
      read $fh, $x0, $reclen;
      read $fh, $x1, $reclen;
    }
    else {
      $x0 = substr( $gi->{buf}, $offset * 2 * $reclen, $reclen );
      $x1 = substr( $gi->{buf}, $offset * 2 * $reclen + $reclen, $reclen );
    }

    $x0 = unpack( "V1", $x0 . "\0" );
    $x1 = unpack( "V1", $x1 . "\0" );

    if ( $ipnum & ( 1 << $depth ) ) {
      if ( $x1 >= $gi->{"databaseSegments"} ) {
	    $gi->{last_netmask} = 32 - $depth;
        return $x1;
      }
      $offset = $x1;
    }
    else {
      if ( $x0 >= $gi->{"databaseSegments"} ) {
	    $gi->{last_netmask} = 32 - $depth;
        return $x0;
      }
      $offset = $x0;
    }
  }

  print STDERR
"Error Traversing Database for ipnum = $ipnum - Perhaps database is corrupt?";
}

sub charset {
  return $_[0]->{_charset};
}

sub set_charset{
  my ($gi, $charset) = @_;
  my $old_charset = $gi->{_charset};
  $gi->{_charset} = $charset;
  return $old_charset;
}

#this function returns the country code of ip address
sub country_code_by_addr {
  my ( $gi, $ip_address ) = @_;
  return unless $ip_address =~ m!^(?:\d{1,3}\.){3}\d{1,3}$!;
  return $countries[ $gi->id_by_addr($ip_address) ];
}

#this function returns the country code3 of ip address
sub country_code3_by_addr {
  my ( $gi, $ip_address ) = @_;
  return unless $ip_address =~ m!^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$!;
  return $code3s[ $gi->id_by_addr($ip_address) ];
}

sub id_by_addr {
  my ( $gi, $ip_address ) = @_;
  return unless $ip_address =~ m!^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$!;
  return $gi->_seek_country( addr_to_num($ip_address) ) - GEOIP_COUNTRY_BEGIN;
}

#this function returns the country code of domain name
sub country_code_by_name {
  my ( $gi, $host ) = @_;
  my $country_id = $gi->id_by_name($host);
  return $countries[$country_id];
}

#this function returns the country code3 of domain name
sub country_code3_by_name {
  my ( $gi, $host ) = @_;
  my $country_id = $gi->id_by_name($host);
  return $code3s[$country_id];
}

sub id_by_name {
  my ( $gi, $host ) = @_;
  my $ip_address;
  if ( $host =~ m!^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$! ) {
    $ip_address = $host;
  }
  else {
    $ip_address = join( '.', unpack( 'C4', ( gethostbyname($host) )[4] ) );
  }
  return unless $ip_address;
  return $gi->_seek_country( addr_to_num($ip_address) ) - GEOIP_COUNTRY_BEGIN;
}

sub get_ip_address {
  my ( $gi, $host ) = @_;
  my $ip_address;

  #check if host is ip address
  if ( $host =~ m!^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$! ) {

    #host is ip address
    $ip_address = $host;
  }
  else {

    #host is domain name do a dns lookup
    $ip_address = join( '.', unpack( 'C4', ( gethostbyname($host) )[4] ) );
  }
  return $ip_address;
}

sub addr_to_num { unpack( N => pack( C4 => split( /\./, $_[0] ) ) ) }
sub num_to_addr { join q{.}, unpack( C4 => pack( N => $_[0] ) ) }

#sub addr_to_num {
#  my @a = split( '\.', $_[0] );
#  return $a[0] * 16777216 + $a[1] * 65536 + $a[2] * 256 + $a[3];
#}

sub database_info {
  my $gi = shift;
  my $i  = 0;
  my $buf;
  my $retval;
  my $hasStructureInfo;
  seek( $gi->{fh}, -3, 2 );
  for ( my $i = 0; $i < STRUCTURE_INFO_MAX_SIZE; $i++ ) {
    read( $gi->{fh}, $buf, 3 );
    if ( $buf eq ( chr(255) . chr(255) . chr(255) ) ) {
      $hasStructureInfo = 1;
      last;
    }
    seek( $gi->{fh}, -4, 1 );
  }
  if ( $hasStructureInfo == 1 ) {
    seek( $gi->{fh}, -6, 1 );
  }
  else {

    # no structure info, must be pre Sep 2002 database, go back to
    seek( $gi->{fh}, -3, 2 );
  }
  for ( my $i = 0; $i < DATABASE_INFO_MAX_SIZE; $i++ ) {
    read( $gi->{fh}, $buf, 3 );
    if ( $buf eq ( chr(0) . chr(0) . chr(0) ) ) {
      read( $gi->{fh}, $retval, $i );
      return $retval;
    }
    seek( $gi->{fh}, -4, 1 );
  }
  return '';
}

sub netmask { $_[0]->{last_netmask} = $_[1] }

sub last_netmask {
  return $_[0]->{last_netmask};
}

sub DESTROY {
  my $gi = shift;
 
  if ( exists $gi->{buf} && $gi->{flags} && ( $gi->{flags} & GEOIP_MMAP_CACHE ) ) {
    munmap( $gi->{buf} ) or die "munmap: $!";
	  delete $gi->{buf};
  }
}

#sub _XS
__PP_CODE__

print STDERR $@ if $@;

@EXPORT = qw(
  GEOIP_STANDARD              GEOIP_MEMORY_CACHE
  GEOIP_CHECK_CACHE           GEOIP_INDEX_CACHE
  GEOIP_UNKNOWN_SPEED         GEOIP_DIALUP_SPEED
  GEOIP_CABLEDSL_SPEED        GEOIP_CORPORATE_SPEED
  GEOIP_COUNTRY_EDITION       GEOIP_REGION_EDITION_REV0
  GEOIP_CITY_EDITION_REV0     GEOIP_ORG_EDITION
  GEOIP_ISP_EDITION           GEOIP_CITY_EDITION_REV1
  GEOIP_REGION_EDITION_REV1   GEOIP_PROXY_EDITION
  GEOIP_ASNUM_EDITION         GEOIP_NETSPEED_EDITION
  GEOIP_CHARSET_ISO_8859_1    GEOIP_CHARSET_UTF8
  GEOIP_MMAP_CACHE
);

1;
