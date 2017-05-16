package Math::Base62;

use base "Exporter";
our @EXPORT = qw(encode_base62 decode_base62);

$i = 0;
for(0..9, 'A'..'Z', 'a'..'z') {
	$base62{$i} = $_;
	$read_base62{$_} = $i;
	$i++;
}

sub encode_base62($) {
	my($value) = @_;
	my $digits = "";
	while($value) {
		use integer;
		$digits .= $base62{$value % 62};
		$value /= 62;
	}
	return scalar(reverse($digits));
}

sub decode_base62($) {
	my($digits) = @_;
	my $value = 0;
	while($digits =~ /(.)/sg) {
		$value = 62 * $value + $read_base62{$1};
	}
	return $value;
}

1;
