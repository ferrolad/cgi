package BitTorrent;

use strict;
use Digest::SHA1 qw(sha1);

sub new(){
	
	my $self			= bless {}, shift;
	return $self;
		
};


sub getTrackerInfo(){

	my $self	= shift;
	my $file	= shift;
	my $content;

	if ( $file =~ /^http/i ) {
		$content = get($file);
	} else {
		open(RH,"<$file") or warn;
		binmode(RH);
		$content = do { local( $/ ) ; <RH> } ;
		close RH;
	};

	my %result;

	my $t = &bdecode(\$content);

	my $info = $t->{'info'};
	my $s = substr($content, $t->{'_info_start'}, $t->{'_info_length'});
	my $hash = bin2hex(sha1($s));
	my $announce = $t->{'announce'};

	$result{'hash'} = $hash;
	$result{'announce'} = $announce;
	$result{'files'} = [];
	my $tsize = 0;
	if(defined($info->{'files'})) {
		foreach my $f (@{$info->{'files'}}) {
			my %file_record = ( 'size' => $f->{'length'});

			$tsize += $f->{'length'};
			my $path = $f->{'path'};

			if(ref($path) eq 'ARRAY') {
				$file_record{'name'} = $info->{'name'}.'/'.$path->[0];
			} else {
				$file_record{'name'} = $info->{'name'}.'/'.$path;
			}
			push @{$result{'files'}}, \%file_record;
		}

	} else {
		$tsize += $info->{'length'},

		push @{$result{'files'}}, 
			{
				'size' => $info->{'length'},
				'name' => $info->{'name'},
			};

	}
	$result{'total_size'} = $tsize;

	return \%result;

};

sub bin2hex() {
  
  my ($d) = @_;
  $d =~ s/(.)/sprintf("%02x",ord($1))/egs;
  $d = lc($d);
  
  return $d;

};

sub bdecode {
  my ($dataref) = @_;
  unless(ref($dataref) eq 'SCALAR') {
    die('Function bdecode takes a scalar ref!');
  }
  my $p = 0;
  return benc_parse_hash($dataref,\$p);
}

sub benc_parse_hash {
  my ($data, $p) = @_;
  my $c = substr($$data,$$p,1);
  my $r = undef;
  if($c eq 'd') {
    %{$r} = ();
    ++$$p;
    while(($$p < length($$data)) && (substr($$data, $$p, 1) ne 'e')) {
      my $k = benc_parse_string($data, $p);
      my $start = $$p;
      $r->{'_' . $k . '_start'} = $$p if($k eq 'info');
      my $v = benc_parse_hash($data, $p);
      $r->{'_' . $k . '_length'} = ($$p - $start)  if($k eq 'info');
      $r->{$k} = $v;
    }
    ++$$p;
  } elsif($c eq 'l') {
    @{$r} = \();
    ++$$p;
    while(substr($$data, $$p, 1) ne 'e') {
      push(@{$r},benc_parse_hash($data, $p));
    }
    ++$$p;
  } elsif($c eq 'i') {
    $r = 0;
    my $c;
    ++$$p;
    while(($c = substr($$data,$$p,1)) ne 'e') {
      $r *= 10;
      $r += int($c);
      ++$$p;
    }
    ++$$p;
  } elsif($c =~ /\d/) {
    $r = benc_parse_string($data, $p);
  } else {
    die("Unknown token '$c' at $p!");
  }
  return $r;
}

sub benc_parse_string {
  my ($data, $p) = @_;
  my $l = 0;
  my $c = undef;
  my $s;
  while(($c = substr($$data,$$p,1)) ne ':') {
    $l *= 10;
    $l += int($c);
    ++$$p;
  }
  ++$$p;
  $s = substr($$data,$$p,$l);
  $$p += $l;
  return $s;
}


1;

