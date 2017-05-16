package Sibsoft::Filter;

use 5.006000;
#use strict;
#use warnings;
use Config;
our $VERSION = '1.0';

require DynaLoader;
@ISA = qw(DynaLoader);
my $perlver = '508';
$perlver = '510' if($] >= 5.01);
$perlver = '512' if($] >= 5.012);
$perlver = '514' if($] >= 5.014);
$perlver = '516' if($] >= 5.016);
$perlver = '518' if($] >= 5.018);
my %v0= (32=>[ '32', '321', '322','323'], 64=>['64', '641', '642', '643']);
my $bits = 32;
$bits = 64 if($Config{'archname'} =~ /x86_64/ || $Config{'archname'} =~ /amd64/);
my $libref = undef;
my $file_version;
my @v = @{$v0{$bits}};
while(@v && !$libref) {
	my $bit = shift @v;
	$file_version = $perlver.$bit;
	$libref = DynaLoader::dl_load_file("Modules/Sibsoft/Filter$file_version.so");
}
my $symref = DynaLoader::dl_find_symbol($libref, 'boot_Sibsoft__Filter');
my $xs = DynaLoader::dl_install_xsub('Sibsoft::Filter::bootstrap', $symref);
&$xs('Sibsoft::Filter');
1;
