package MP3::Info;

require 5.006;

use strict;
use overload;
use Carp;
use Fcntl qw(:seek);

use vars qw(
	@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION $REVISION
	@mp3_genres %mp3_genres @winamp_genres %winamp_genres $try_harder
	@t_bitrate @t_sampling_freq @frequency_tbl %v1_tag_fields
	@v1_tag_names %v2_tag_names %v2_to_v1_names $AUTOLOAD
	@mp3_info_fields %rva2_channel_types
	$debug_24 $debug_Tencoding
);

@ISA = 'Exporter';
@EXPORT = qw(
	get_mp3tag get_mp3info use_winamp_genres
);
@EXPORT_OK = qw(@mp3_genres %mp3_genres use_mp3_utf8);
%EXPORT_TAGS = (
	genres	=> [qw(@mp3_genres %mp3_genres)],
	utf8	=> [qw(use_mp3_utf8)],
	all	=> [@EXPORT, @EXPORT_OK]
);


($REVISION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
$VERSION = '1.24';


$debug_24 = 0;
$debug_Tencoding = 0;


{
	my $c = -1;


	%mp3_genres = map {($_, ++$c, lc, $c)} @mp3_genres;


	$c = -1;
	%winamp_genres = map {($_, ++$c, lc, $c)} @winamp_genres;
}


sub new {
	my($pack, $file) = @_;

	my $info = get_mp3info($file) or return undef;
	my $tags = get_mp3tag($file) || { map { ($_ => undef) } @v1_tag_names };
	my %self = (
		FILE		=> $file,
		TRY_HARDER	=> 0
	);

	@self{@mp3_info_fields, @v1_tag_names, 'file'} = (
		@{$info}{@mp3_info_fields},
		@{$tags}{@v1_tag_names},
		$file
	);

	return bless \%self, $pack;
}

sub can {
	my $self = shift;
	return $self->SUPER::can(@_) unless ref $self;
	my $name = uc shift;
	return sub { $self->$name(@_) } if exists $self->{$name};
	return undef;
}

sub AUTOLOAD {
	my($self) = @_;
	(my $name = uc $AUTOLOAD) =~ s/^.*://;

	if (exists $self->{$name}) {
		my $sub = exists $v1_tag_fields{$name}
			? sub {
				if (defined $_[1]) {
					$_[0]->{$name} = $_[1];
					set_mp3tag($_[0]->{FILE}, $_[0]);
				}
				return $_[0]->{$name};
			}
			: sub {
				return $_[0]->{$name}
			};

		no strict 'refs';
		*{$AUTOLOAD} = $sub;
		goto &$AUTOLOAD;

	} else {
		carp(sprintf "No method '$name' available in package %s.",
			__PACKAGE__);
	}
}

sub DESTROY {

}


=item use_mp3_utf8([STATUS])

Tells MP3::Info to (or not) return TAG info in UTF-8.
TRUE is 1, FALSE is 0.  Default is TRUE, if available.

Will only be able to turn it on if Encode is available.  ID3v2
tags will be converted to UTF-8 according to the encoding specified
in each tag; ID3v1 tags will be assumed Latin-1 and converted
to UTF-8.

Function returns status (TRUE/FALSE).  If no argument is supplied,
or an unaccepted argument is supplied, function merely returns status.

This function is not exported by default, but may be exported
with the C<:utf8> or C<:all> export tag.

=cut

my $unicode_base_module = eval { require Encode; require Encode::Guess };

my $UNICODE = use_mp3_utf8($unicode_base_module ? 1 : 0);

eval { require Encode::Detect::Detector };

my $unicode_detect_module = $@ ? 0 : 1;

sub use_mp3_utf8 {
	my $val = shift;

	$UNICODE = 0;

	if ($val == 1) {

		if ($unicode_base_module) {

			$Encode::Guess::NoUTFAutoGuess = 1;
			$UNICODE = 1;
		}
	}

	return $UNICODE;
}

=pod

=item use_winamp_genres()

Puts WinAmp genres into C<@mp3_genres> and C<%mp3_genres>
(adds 68 additional genres to the default list of 80).
This is a separate function because these are non-standard
genres, but they are included because they are widely used.

You can import the data structures with one of:

	use MP3::Info qw(:genres);
	use MP3::Info qw(:DEFAULT :genres);
	use MP3::Info qw(:all);

=cut

sub use_winamp_genres {
	%mp3_genres = %winamp_genres;
	@mp3_genres = @winamp_genres;
	return 1;
}

sub get_mp3tag {
	my $file     = shift;
	my $ver      = shift || 0;
	my $raw      = shift || 0;
	my $find_ape = shift || 0;
	my $fh;

	my $has_v1  = 0;
	my $has_v2  = 0;
	my $has_ape = 0;
	my %info    = ();


	$ver = !$ver ? 0 : ($ver == 2 || $ver == 1) ? $ver : 0;

	if (!(defined $file && $file ne '')) {
		$@ = "No file specified";
		return undef;
	}

	my $filesize = -s $file;

	if (!$filesize) {
		$@ = "File is empty";
		return undef;
	}


	if (ref $file) {

		$fh = $file;

	} else {

		open($fh, $file) || do {
			$@ = "Can't open $file: $!";
			return undef;
		};
	}

	binmode $fh;



	if ($find_ape) {

		$has_ape = _parse_ape_tag($fh, $filesize, \%info);
	}

	if ($ver < 2) {

		$has_v1 = _get_v1tag($fh, \%info);

		if ($ver == 1 && !$has_v1) {
			_close($file, $fh);
			$@ = "No ID3v1 tag found";
			return undef;
		}
	}

	if ($ver == 2 || $ver == 0) {
		$has_v2 = _get_v2tag($fh, $ver, $raw, \%info);
	}

	if (!$has_v1 && !$has_v2 && !$has_ape) {
		_close($file, $fh);
		$@ = "No ID3 or APE tag found";
		return undef;
	}

	unless ($raw && $ver == 2) {


		foreach my $key (keys %info) {

			if (defined $info{$key}) {
				$info{$key} =~ s/\000+.*//g;
				$info{$key} =~ s/\s+$//;
			}
		}

		for (@v1_tag_names) {
			$info{$_} = '' unless defined $info{$_};
		}
	}

	if (keys %info && !defined $info{'GENRE'}) {
		$info{'GENRE'} = '';
	}

	_close($file, $fh);

	return keys %info ? \%info : undef;
}

sub _get_v1tag {
	my ($fh, $info) = @_;

	seek $fh, -128, SEEK_END;
	read($fh, my $tag, 128);

	if (!defined($tag) || $tag !~ /^TAG/) {

		return 0;
	}

	if (substr($tag, -3, 2) =~ /\000[^\000]/) {

		(undef, @{$info}{@v1_tag_names}) =
			(unpack('a3a30a30a30a4a28', $tag),
			ord(substr($tag, -2, 1)),
			$mp3_genres[ord(substr $tag, -1)]);

		$info->{'TAGVERSION'} = 'ID3v1.1';

	} else {

		(undef, @{$info}{@v1_tag_names[0..4, 6]}) =
			(unpack('a3a30a30a30a4a30', $tag),
			$mp3_genres[ord(substr $tag, -1)]);

		$info->{'TAGVERSION'} = 'ID3v1';
	}

	if (!$UNICODE) {
		return 1;
	}




	my $oldSuspects = $Encode::Encoding{'Guess'}->{'Suspects'};

	for my $key (keys %{$info}) {

		next unless $info->{$key};


		if ($unicode_detect_module) {

			my $charset = Encode::Detect::Detector::detect($info->{$key}) || 'iso-8859-1';
			my $enc     = Encode::find_encoding($charset);

			if ($enc) {

				$info->{$key} = $enc->decode($info->{$key}, 0);

				next;
			}
		}

		my $value = $info->{$key};
		my $icode = Encode::Guess->guess($value);

		if (!ref($icode)) {



			#Encode::Guess->add_suspects('iso-8859-1');
                   Encode::Guess->add_suspects(qw/cp1251/);

			while (length($value)) {

				$icode = Encode::Guess->guess($value);

				last if ref($icode);




				$value =~ s/(.)$//;
			}
		}

		$info->{$key} = Encode::decode(ref($icode) ? $icode->name : 'iso-8859-1', $info->{$key});
		

		$info->{$key} =~ s/\x00+$//g;
	}

	Encode::Guess->set_suspects(keys %{$oldSuspects});

	return 1;
}

sub _parse_v2tag {
	my ($ver, $raw_v2, $v2, $info) = @_;



	if ($v2->{'TXXX'} && ref($v2->{'TXXX'}) ne 'ARRAY') {

		$v2->{'TXXX'} = [ $v2->{'TXXX'} ];
	}



	if (ref($v2->{'COMM'}) eq 'ARRAY' && grep { /Media Jukebox/ } @{$v2->{'COMM'}}) {

		for my $comment (@{$v2->{'COMM'}}) {

			if ($comment =~ /Media Jukebox/) {


				$comment =~ s/^\000+//g;

				push @{$v2->{'TXXX'}}, "\000$comment";
			}
		}
	}

	my $hash = $raw_v2 == 2 ? { map { ($_, $_) } keys %v2_tag_names } : \%v2_to_v1_names;

	for my $id (keys %{$hash}) {

		next if !exists $v2->{$id};

		if ($id =~ /^UFID?$/) {

			my @ufid_list = split(/\0/, $v2->{$id});

			$info->{$hash->{$id}} = $ufid_list[1] if ($#ufid_list > 0);

		} elsif ($id =~ /^RVA[D2]?$/) {


			if ($id eq 'RVA2') {


				($info->{$hash->{$id}}->{'ID'}, my $rvad) = split /\0/, $v2->{$id};

				my $channel = $rva2_channel_types{ ord(substr($rvad, 0, 1, '')) };

				$info->{$hash->{$id}}->{$channel}->{'REPLAYGAIN_TRACK_GAIN'} = 
					sprintf('%f', _grab_int_16(\$rvad) / 512);

				my $peakBytes = ord(substr($rvad, 0, 1, ''));

				if (int($peakBytes / 8)) {

					$info->{$hash->{$id}}->{$channel}->{'REPLAYGAIN_TRACK_PEAK'} = 
						sprintf('%f', _grab_int_16(\$rvad) / 512);
				}

			} elsif ($id eq 'RVAD' || $id eq 'RVA') {

				my $rvad  = $v2->{$id};
				my $flags = ord(substr($rvad, 0, 1, ''));
				my $desc  = ord(substr($rvad, 0, 1, ''));



				for my $type (qw(REPLAYGAIN_TRACK_GAIN REPLAYGAIN_TRACK_PEAK)) {

					for my $channel (qw(RIGHT LEFT)) {

						my $val = _grab_uint_16(\$rvad) / 256;



						if ($val == -255) {
							$val = -96.0;
						} else {
							$val = 20.0 * log(($val+255)/255)/log(10);
						}

						$info->{$hash->{$id}}->{$channel}->{$type} = $flags & 0x01 ? $val : -$val;
					}
				}
			}

		} elsif ($id =~ /^A?PIC$/) {

			my $pic = $v2->{$id};







			if (ref($pic) eq 'ARRAY') {
				$pic = (@$pic)[0];
			}

			use bytes;

			my $valid_pic  = 0;
			my $pic_len    = 0;
			my $pic_format = '';


			if ($pic && $id eq 'PIC') {


				my ($encoding, $format, $picture_type, $description) = unpack 'Ca3CZ*', $pic;
				$pic_len = length($description) + 1 + 5;


				if ($encoding) { $pic_len++; }

				if ($pic_len < length($pic)) {
					$valid_pic  = 1;
					$pic_format = $format;
				}

			} elsif ($pic && $id eq 'APIC') {


				my ($encoding, $format) = unpack 'C Z*', $pic;

				$pic_len = length($format) + 2;

				if ($pic_len < length($pic)) {

					my ($picture_type, $description) = unpack "x$pic_len C Z*", $pic;

					$pic_len += 1 + length($description) + 1;


					if ( $encoding == 1 || $encoding == 2 ) { $pic_len++; }

					$valid_pic  = 1;
					$pic_format = $format;
				}
			}


			if ($valid_pic && $pic_format) {

				my ($data) = unpack("x$pic_len A*", $pic);

				if (length($data) && $pic_format) {

					$info->{$hash->{$id}} = {
						'DATA'   => $data,
						'FORMAT' => $pic_format,
					}
				}
			}

		} else {
			my $data1 = $v2->{$id};

			$data1 = [ $data1 ] if ref($data1) ne 'ARRAY';

			for my $data (@$data1) {




				$data =~ s/^(.)//; # strip first char (text encoding)
				my $encoding = $1;
				my $desc;


				if ($id =~ /^(COM[M ]?|US?LT)$/) { # space for iTunes brokenness

					$data =~ s/^(?:...)//;		# strip language
				}



				if ($UNICODE) {

					if ($encoding eq "\001" || $encoding eq "\002") {  # UTF-16, UTF-16BE


						#





						$data = eval { Encode::decode('utf16', $data) } || Encode::decode('utf16le', $data);

					} elsif ($encoding eq "\003") { # UTF-8


						$data = Encode::decode('utf8', $data);

					} elsif ($encoding eq "\000") {


						if ($data && $data !~ /^[\x00-\x7F]+$/) {

							if ($unicode_detect_module) {

								my $charset = Encode::Detect::Detector::detect($data) || 'iso-8859-1';
								my $enc     = Encode::find_encoding($charset);

								if ($enc) {
									$data = $enc->decode($data, 0);
								}

							} else {


								my $dec = Encode::Guess->guess($data);

								if (ref $dec) {
									$data = $dec->decode($data);
								} else {

									$data = Encode::decode('iso-8859-1', $data);
								}
							}
						}
					}

				} else {




					my $pat;
					if ($data =~ s/^\xFF\xFE//) {

						$data = join ("",map { ( /^(..)$/ && ! /(\xFF\xFE)/ )? $_: "" } (split /(..)/, $data));
						$pat = 'v';
					} elsif ($data =~ s/^\xFE\xFF//) {

						$data = join ("",map { ( /^(..)$/ && ! /(\xFF\xFE)/ )? $_: "" } (split /(..)/, $data));
						$pat = 'n';
					}

					if ($pat) {

						$data = join ("",map { ( /^(..)$/ && ! /(\x00\x00)/ )? $_: "" } (split /(..)/, $data));
						$data = pack 'C*', map {
							(chr =~ /[[:ascii:]]/ && chr =~ /[[:print:]]/)
								? $_
								: ord('?')
						} unpack "$pat*", $data;
					}
				}



				if ($id =~ /^(COM[M ]?|US?LT)$/) { # space for iTunes brokenness

					$data =~ s/^(.*?)\000//;	# strip up to first NULL(s),


					$desc = $1;

					if ($encoding eq "\001" || $encoding eq "\002") {

						$data =~ s/^\x{feff}//;
					}

				} elsif ($id =~ /^TCON?$/) {

					my ($index, $name);


					$data =~ s/\000+/\000/g;


					#


					if ($data =~ /^ \(? (\d+) \)?\000?$/sx) {

						$index = $1;



					} elsif ($data =~ /^ \( (\d+) \)\000? ([^\(].+)$/x) {

						($index, $name) = ($1, $2);


					} elsif ($data =~ /^ \( (\d+) \)\000?/x) {

						my @genres = ();

						while ($data =~ s/^ \( (\d+) \)//x) {




							if ($data =~ s/^ ( [^\(]\D+ ) ( \000 | \( | \Z)/$2/x) {

								push @genres, $1;

							} else {

								push @genres, $mp3_genres[$1];
							}
						}

						$data = \@genres;

					} elsif ($data =~ /^[^\000]+\000/) {


						$data = [ split /\000/, $data ];
					}


					if ($name && $name ne "\000") {
						$data = $name;
					} elsif (defined $index) {
						$data = $mp3_genres[$index];
					}


					if ($data && ref($data) eq 'ARRAY' && scalar @$data == 1) {

						$data = $data->[0];
					}

				} elsif ($id =~ /^T...?$/ && $id ne 'TXXX') {
					







					


					$data =~ s/\x00+$//;

					
					if ($data =~ /\x00/ && ($raw_v2 == 2 || $raw_v2 == 0))
					{





						$data = [ split /\000/, $data ];
					}
				}

				if ($desc)
				{


					if ($raw_v2 == 2) {

						$data = { $desc => $data };

					} elsif ($desc =~ /^iTun/) {


						$data = join(' ', $desc, $data);
					}
				}

				if ($raw_v2 == 2 && exists $info->{$hash->{$id}}) {

					if (ref $info->{$hash->{$id}} eq 'ARRAY') {
						push @{$info->{$hash->{$id}}}, $data;
					} else {
						$info->{$hash->{$id}} = [ $info->{$hash->{$id}}, $data ];
					}

				} else {


					if ($id eq 'TXXX') {

						my ($key, $val) = split(/\0/, $data);


						if ($encoding eq "\001" || $encoding eq "\002") {

							$val =~ s/^\x{feff}//;
						}

						$info->{uc($key)} = $val;

					} elsif ($id eq 'PRIV') {

						my ($key, $val) = split(/\0/, $data);
						$info->{uc($key)} = unpack('v', $val);

					} else {

						my $key = $hash->{$id};




						if ($ver == 2 && $info->{$key} && !ref($info->{$key})) {

							if (ref($data) eq "ARRAY") {
							
								$info->{$key} = [ $info->{$key}, @$data ];
							} else {
							
								my $old = delete $info->{$key};
							
								@{$info->{$key}} = ($old, $data);
							}

						} elsif ($ver == 2 && ref($info->{$key}) eq 'ARRAY') {
							
							if (ref($data) eq "ARRAY") {

								push @{$info->{$key}}, @$data;

							} else {

								push @{$info->{$key}}, $data;
							}

						} else {

							$info->{$key} = $data;
						}
					}
				}
			}
		}
	}
}

sub _get_v2tag {
	my ($fh, $ver, $raw, $info, $start) = @_;
	my $eof;
	my $gotanyv2 = 0;



	seek $fh, -128, SEEK_END;
	$eof = (tell $fh) + 128;


	if (<$fh> =~ /^TAG/) {
		$eof -= 128;
	}

	seek $fh, $eof, SEEK_SET;


	if (my $v2f = _get_v2foot($fh)) {
		$eof -= $v2f->{tag_size};

		$gotanyv2 |= (_get_v2tagdata($fh, $ver, $raw, $info, $eof) ? 2 : 0);
	}


	$gotanyv2 |= (_get_v2tagdata($fh, $ver, $raw, $info, $start) ? 1 : 0);





	for my $name (keys %{$info})
	{









	  if (ref $info->{$name} eq 'ARRAY')
	  {
	    my @array = ();
	    my ($i, $o);
	    my @chk = @{$info->{$name}};
	    for $i ( 0..$#chk )
	    {
	      my $ielement = $chk[$i];
	      if (defined $ielement)
	      {
	        for $o ( ($i+1)..$#chk )
	        {
	          $chk[$o] = undef if (defined $o && defined $chk[$o] && ($ielement eq $chk[$o]));
	        }
	        push @array, $ielement;
	      }
	    }


	    if ($#array == 0)
	    { 
	      $info->{$name} = $array[0];
	    }
	    else
	    { 
	      $info->{$name} = \@array;
	    }
	  }
	}

	return $gotanyv2;
}

sub _get_v2tagdata {
	my($fh, $ver, $raw, $info, $start) = @_;
	my($off, $end, $myseek, $v2, $v2h, $hlen, $num, $wholetag);

	$v2 = {};
	$v2h = _get_v2head($fh, $start) or return 0;

	if ($v2h->{major_version} < 2) {
		carp "This is $v2h->{version}; " .
		     "ID3v2 versions older than ID3v2.2.0 not supported\n"
		     if $^W;
		return 0;
	}


	my $id3v2_4_frame_size_broken = 0;
	my $bytesize = ($v2h->{major_version} > 3) ? 128 : 256;


	if ($v2h->{major_version} == 2) {
		$hlen = 6;
		$num = 3;
	} else {
		$hlen = 10;
		$num = 4;
	}

	$off = $v2h->{ext_header_size} + 10;
	$end = $v2h->{tag_size} + 10; # should we read in the footer too?

	return 0 if ($v2h->{major_version} == 2 && $v2h->{compression});



	if ($v2h->{update}) {
		$v2 = $info;
	}


	my $size = -s $fh;
	if ( $v2h->{offset} + $end > $size ) {
		$end -= $v2h->{offset} + $end - $size;
	}

	seek $fh, $v2h->{offset}, SEEK_SET;
	read $fh, $wholetag, $end;










	if ($v2h->{major_version} == 4) {
		$v2h->{unsync} = 0
	}

	$wholetag =~ s/\xFF\x00/\xFF/gs if $v2h->{unsync};















	$myseek = sub {
		return unless $wholetag;
		
		my $bytes = substr($wholetag, $off, $hlen);



		if ($bytes !~ /^([A-Z0-9\? ]{$num})/) {
			return;
		}

		my ($id, $size) = ($1, $hlen);
		my @bytes = reverse unpack "C$num", substr($bytes, $num, $num);

		for my $i (0 .. ($num - 1)) {
			$size += $bytes[$i] * $bytesize ** $i;
		}







		if ($v2h->{major_version}==4 && 
		    $id3v2_4_frame_size_broken == 0 && # we haven't detected brokenness yet
		    ((($bytes[0] | $bytes[1] | $bytes[2] | $bytes[3]) & 0x80) != 0 || # 0-bits set in size
		     $off + $size > $end)  # frame size would excede the tag end
		    )
		{


		  $bytesize = 128;
		  $size -= $hlen; # hlen has alread been added, so take that off again
		  $size = (($size & 0x0000007f)) | 
		          (($size & 0x00003f80)<<1) |
		          (($size & 0x001fc000)<<2) |
		          (($size & 0x0fe00000)<<3); # convert spec to non-spec sizes

		  $size += $hlen; # and re-add header len so that the entire frame's size is known

		  $id3v2_4_frame_size_broken = 1;

		  print "Frame size cannot be valid ID3v2.4 (part 1); reverting to broken behaviour\n" if ($debug_24);

		}



		if ($v2h->{major_version}==4 && 
		    $id3v2_4_frame_size_broken == 0 && # we haven't detected brokenness yet
		    $size > 0x80+$hlen && # ignore frames that are too short to ever be wrong
		    $off + $size < $end)
		{

		  print "Frame size might not be valid ID3v2.4 (part 2); checking for following frame validity\n" if ($debug_24);

		  my $morebytes = substr($wholetag, $off+$size, 4);

		  if (! ($morebytes =~ /^([A-Z0-9]{4})/ || $morebytes =~ /^\x00{4}/) ) {




		    my $retrysize;

		    print "  following frame isn't valid using spec\n" if ($debug_24);

		    $retrysize = $size - $hlen; # remove already added header length
		    $retrysize = (($retrysize & 0x0000007f)) | 
		                 (($retrysize & 0x00003f80)<<1) |
		                 (($retrysize & 0x001fc000)<<2) |
		                 (($retrysize & 0x0fe00000)<<3); # convert spec to non-spec sizes

		    $retrysize += $hlen; # and re-add header len so that the entire frame's size is known

		    if (length($wholetag) >= ($off+$retrysize+4)) {

		    	$morebytes = substr($wholetag, $off+$retrysize, 4);

		    } else {

		    	$morebytes = '';
		    }

		    if (! ($morebytes =~ /^([A-Z0-9]{4})/ ||
		           $morebytes =~ /^\x00{4}/ ||
		           $off + $retrysize > $end) )
		    {



		      print "  and isn't valid using broken-spec support; giving up\n" if ($debug_24);
		      return;
		    }
		    
		    print "  but is fine with broken-spec support; reverting to broken behaviour\n" if ($debug_24);
		    





		    $size = $retrysize;
		    $bytesize = 128;
		    $id3v2_4_frame_size_broken = 1;

		  } else {

		    print "  looks like valid following frame; keeping spec behaviour\n" if ($debug_24);

		  }
		}

		my $flags = {};


		if ($v2h->{major_version} == 4) {
			my @bits = split //, unpack 'B16', substr($bytes, 8, 2);
			$flags->{frame_zlib}         = $bits[12]; # JRF: need to know about compressed
			$flags->{frame_encrypt}      = $bits[13]; # JRF: ... and encrypt
			$flags->{frame_unsync}       = $bits[14];
			$flags->{data_len_indicator} = $bits[15];
		}


		elsif ($v2h->{major_version} == 3) {
			my @bits = split //, unpack 'B16', substr($bytes, 8, 2);
			$flags->{frame_zlib}         = $bits[8]; # JRF: need to know about compressed
			$flags->{data_len_indicator} = $bits[8]; # JRF:   and compression implies the DLI is present
			$flags->{frame_encrypt}      = $bits[9]; # JRF: ... and encrypt
		}

		return ($id, $size, $flags);
	};

	while ($off < $end) {
		my ($id, $size, $flags) = &$myseek or last;
		my ($hlenextra) = 0;



		if ($flags->{frame_encrypt}) {

			my ($encypt_method) = substr($wholetag, $off+$hlen+$hlenextra, 1);

			$hlenextra++;


			$off += $size;

			next;
		}

		my $bytes = substr($wholetag, $off+$hlen+$hlenextra, $size-$hlen-$hlenextra);

		my $data_len;
		if ($flags->{data_len_indicator}) {
			$data_len = 0;

			my @data_len_bytes = reverse unpack 'C4', substr($bytes, 0, 4);

			$bytes = substr($bytes, 4);

		        for my $i (0..3) {
				$data_len += $data_len_bytes[$i] * 128 ** $i;
		        }
		}

		print "got $id, length " . length($bytes) . " frameunsync: ".$flags->{frame_unsync}." tag unsync: ".$v2h->{unsync} ."\n" if ($debug_24);


		$bytes =~ s/\xFF\x00/\xFF/gs if $flags->{frame_unsync} && !$v2h->{unsync};





		if ($flags->{data_len_indicator} && defined $data_len) {
		        carp("Size mismatch on $id\n") unless $data_len == length($bytes);
		}










		if (($v2h->{major_version} == 3 || $v2h->{major_version} == 4) && $id =~ /^T/) {

			my $encoding = substr($bytes, 0, 1);
		  


			if (($encoding eq "\x00" || $encoding eq "\x03") && $bytes !~ /\x00$/) { 

				$bytes .= "\x00"; 
				print "Text frame $id has malformed ISO-8859-1/UTF-8 content\n" if ($debug_Tencoding);


			} elsif ( ($encoding eq "\x01" || $encoding eq "\x02") && $bytes !~ /\x00\x00$/) { 

				$bytes .= "\x00\x00";
				print "Text frame $id has malformed UTF-16/UTF-16BE content\n" if ($debug_Tencoding);

			} else {


			}
		}

		if (exists $v2->{$id}) {

			if (ref $v2->{$id} eq 'ARRAY') {
				push @{$v2->{$id}}, $bytes;
			} else {
				$v2->{$id} = [$v2->{$id}, $bytes];
			}

		} else {

			$v2->{$id} = $bytes;
		}

		$off += $size;
	}

	if (($ver == 0 || $ver == 2) && $v2) {

		if ($raw == 1 && $ver == 2) {

			%$info = %$v2;

			$info->{'TAGVERSION'} = $v2h->{'version'};

		} else {

			_parse_v2tag($ver, $raw, $v2, $info);

			if ($ver == 0 && $info->{'TAGVERSION'}) {
				$info->{'TAGVERSION'} .= ' / ' . $v2h->{'version'};
			} else {
				$info->{'TAGVERSION'} = $v2h->{'version'};
			}
		}
	}

	return 1;
}


sub get_mp3info {
	my($file) = @_;
	my($off, $byte, $eof, $h, $tot, $fh);

	if (not (defined $file && $file ne '')) {
		$@ = "No file specified";
		return undef;
	}
	
	my $size = -s $file;

	if (ref $file) { # filehandle passed
		$fh = $file;
	} else {
		if ( !$size ) {
			$@ = "File is empty";
			return undef;
		}
		
		if (not open $fh, '<', $file) {
			$@ = "Can't open $file: $!";
			return undef;
		}
	}

	$off = 0;
	$tot = 8192;


	if ($try_harder) {
		$tot *= $try_harder;
	}

	binmode $fh;
	seek $fh, $off, SEEK_SET;
	read $fh, $byte, 4;

	if (my $v2h = _get_v2head($fh)) {
		$tot += $off += $v2h->{tag_size};
		
		if ( $off > $size - 10 ) {

			$off = 0;
		}
		
		seek $fh, $off, SEEK_SET;
		read $fh, $byte, 4;
	}

	$h = _get_head($byte);
	my $is_mp3 = _is_mp3($h); 


	unless ($is_mp3) {


		$off++;
		seek $fh, $off, SEEK_SET;
		read $fh, $byte, $tot;
		 
		my $i;
		 

		for ($i = 0; $i < $tot; $i++) {

			last if ($tot - $i) < 4;
		 
			my $head = substr($byte, $i, 4) || last;
			 
			next if (ord($head) != 0xff);
			 
			$h = _get_head($head);
			$is_mp3 = _is_mp3($h);
			last if $is_mp3;
		}
		 

		$off += $i;

		if ($off > $tot && !$try_harder) {
			_close($file, $fh);
			$@ = "Couldn't find MP3 header (perhaps set " .
			     '$MP3::Info::try_harder and retry)';
			return undef;
		}
	}
	
	$h->{offset} = $off;

	my $vbr  = _get_vbr($fh, $h, \$off);
	my $lame = _get_lame($fh, $h, \$off);
	
	seek $fh, 0, SEEK_END;
	$eof = tell $fh;
	seek $fh, -128, SEEK_END;
	$eof -= 128 if <$fh> =~ /^TAG/ ? 1 : 0;



	seek($fh, $eof, SEEK_SET);

	if (my $v2f = _get_v2foot($fh)) {
		$eof -= $v2f->{tag_size};
	}

	_close($file, $fh);

	$h->{size} = $eof - $off;

	return _get_info($h, $vbr, $lame);
}

sub _get_info {
	my($h, $vbr, $lame) = @_;
	my $i;


	unless ($h->{bitrate} && $h->{fs}) {
		return {};
	}

	$i->{VERSION}	= $h->{IDR} == 2 ? 2 : $h->{IDR} == 3 ? 1 : $h->{IDR} == 0 ? 2.5 : 0;
	$i->{LAYER}	= 4 - $h->{layer};

	if (ref($vbr) eq 'HASH' and $vbr->{is_vbr} == 1) {
		$i->{VBR} = 1;
	} else {
		$i->{VBR} = 0;
	}

	$i->{COPYRIGHT}	= $h->{copyright} ? 1 : 0;
	$i->{PADDING}	= $h->{padding_bit} ? 1 : 0;
	$i->{STEREO}	= $h->{mode} == 3 ? 0 : 1;
	$i->{MODE}	= $h->{mode};

	$i->{SIZE}	= $i->{VBR} == 1 && $vbr->{bytes} ? $vbr->{bytes} : $h->{size};
	$i->{OFFSET}	= $h->{offset};

	my $mfs		= $h->{fs} / ($h->{ID} ? 144000 : 72000);
	$i->{FRAMES}	= int($i->{VBR} == 1 && $vbr->{frames}
				? $vbr->{frames}
				: $i->{SIZE} / ($h->{bitrate} / $mfs)
			  );

	if ($i->{VBR} == 1) {
		$i->{VBR_SCALE}	= $vbr->{scale} if $vbr->{scale};
		$h->{bitrate}	= $i->{SIZE} / $i->{FRAMES} * $mfs;
		if (not $h->{bitrate}) {
			$@ = "Couldn't determine VBR bitrate";
			return undef;
		}
	}

	$h->{'length'}	= ($i->{SIZE} * 8) / $h->{bitrate} / 10;
	$i->{SECS}	= $h->{'length'} / 100;
	$i->{MM}	= int $i->{SECS} / 60;
	$i->{SS}	= int $i->{SECS} % 60;
	$i->{MS}	= (($i->{SECS} - ($i->{MM} * 60) - $i->{SS}) * 1000);


	$i->{TIME}	= sprintf "%.2d:%.2d", @{$i}{'MM', 'SS'};

	$i->{BITRATE}		= int $h->{bitrate};

	$i->{FRAME_LENGTH}	= int($h->{size} / $i->{FRAMES}) if $i->{FRAMES};
	$i->{FREQUENCY}		= $frequency_tbl[3 * $h->{IDR} + $h->{sampling_freq}];
	
	if ($lame) {
		$i->{LAME} = $lame;
	}

	return $i;
}

sub _get_head {
	my($byte) = @_;
	my($bytes, $h);

	$bytes = _unpack_head($byte);
	@$h{qw(IDR ID layer protection_bit
		bitrate_index sampling_freq padding_bit private_bit
		mode mode_extension copyright original
		emphasis version_index bytes)} = (
		($bytes>>19)&3, ($bytes>>19)&1, ($bytes>>17)&3, ($bytes>>16)&1,
		($bytes>>12)&15, ($bytes>>10)&3, ($bytes>>9)&1, ($bytes>>8)&1,
		($bytes>>6)&3, ($bytes>>4)&3, ($bytes>>3)&1, ($bytes>>2)&1,
		$bytes&3, ($bytes>>19)&3, $bytes
	);

	$h->{bitrate} = $t_bitrate[$h->{ID}][3 - $h->{layer}][$h->{bitrate_index}];
	$h->{fs} = $t_sampling_freq[$h->{IDR}][$h->{sampling_freq}];

	return $h;
}

sub _is_mp3 {
	my $h = $_[0] or return undef;
	return ! (	# all below must be false
		 $h->{bitrate_index} == 0
			||
		 $h->{version_index} == 1
			||
		($h->{bytes} & 0xFFE00000) != 0xFFE00000
			||
		!$h->{fs}
			||
		!$h->{bitrate}
			||
		 $h->{bitrate_index} == 15
			||
		!$h->{layer}
			||
		 $h->{sampling_freq} == 3
			||
		 $h->{emphasis} == 2
			||
		!$h->{bitrate_index}
			||
		($h->{bytes} & 0xFFFF0000) == 0xFFFE0000
			||
		($h->{ID} == 1 && $h->{layer} == 3 && $h->{protection_bit} == 1)




	);
}

sub _vbr_seek {
	my $fh    = shift;
	my $off   = shift;
	my $bytes = shift;
	my $n     = shift || 4;

	seek $fh, $$off, SEEK_SET;
	read $fh, $$bytes, $n;

	$$off += $n;
}

sub _get_vbr {
	my ($fh, $h, $roff) = @_;
	my ($off, $bytes, @bytes);
	my %vbr = (is_vbr => 0);

	$off = $$roff;

	$off += 4;

	if ($h->{ID}) {	# MPEG1
		$off += $h->{mode} == 3 ? 17 : 32;
	} else {	# MPEG2
		$off += $h->{mode} == 3 ? 9 : 17;
	}

	_vbr_seek($fh, \$off, \$bytes);

	if ($bytes =~ /(?:Xing|Info)/) {

		$vbr{is_vbr} = 1 if $bytes =~ /Xing/;

		_vbr_seek($fh, \$off, \$bytes);
		$vbr{flags} = _unpack_head($bytes);
	
		if ($vbr{flags} & 1) {
			_vbr_seek($fh, \$off, \$bytes);
			$vbr{frames} = _unpack_head($bytes);
		}
	
		if ($vbr{flags} & 2) {
			_vbr_seek($fh, \$off, \$bytes);
			$vbr{bytes} = _unpack_head($bytes);
		}
	
		if ($vbr{flags} & 4) {
			_vbr_seek($fh, \$off, \$bytes, 100);


		}
	
		if ($vbr{flags} & 8) { # (quality ind., 0=best 100=worst)
			_vbr_seek($fh, \$off, \$bytes);
			$vbr{scale} = _unpack_head($bytes);
		} else {
			$vbr{scale} = -1;
		}

		$$roff = $off;
	} elsif ($bytes =~ /(?:VBRI)/) {
		$vbr{is_vbr} = 1;
		


		_vbr_seek($fh, \$off, \$bytes, 4);
		_vbr_seek($fh, \$off, \$bytes, 2);
		$vbr{scale} = unpack('l', pack('L', unpack('n', $bytes)));


		_vbr_seek($fh, \$off, \$bytes);
		$vbr{bytes} = _unpack_head($bytes);


		_vbr_seek($fh, \$off, \$bytes);
		$vbr{frames} = _unpack_head($bytes);

		$$roff = $off;
	}

	return \%vbr;
}



sub _get_lame {
	my($fh, $h, $roff) = @_;
	
	my($off, $bytes, @bytes, %lame);

	$off = $$roff;
	

	_vbr_seek($fh, \$off, \$bytes, 9);
	$lame{encoder_version} = $bytes;

	return unless $bytes =~ /^LAME/;


	_vbr_seek($fh, \$off, \$bytes, 12);
	

	_vbr_seek($fh, \$off, \$bytes, 3);
	my $bin = unpack 'B*', $bytes;
	$lame{start_delay} = unpack('N', pack('B32', substr('0' x 32 . substr($bin, 0, 12), -32)));
	$lame{end_padding} = unpack('N', pack('B32', substr('0' x 32 . substr($bin, 12, 12), -32)));
	
	return \%lame;
}




sub _get_v2head {
	my $fh = $_[0] or return;

	my $v2h = {
		'offset'   => $_[1] || 0,
		'tag_size' => 0,
	};


	seek($fh, $v2h->{offset}, SEEK_SET);
	read($fh, my $header, 10);

	my $tag = substr($header, 0, 3);


	if ($v2h->{offset} == 0) {


		if ($tag eq 'RIF' || $tag eq 'FOR') {
			_find_id3_chunk($fh, $tag) or return;
			$v2h->{offset} = tell $fh;

			read($fh, $header, 10);
			$tag = substr($header, 0, 3);
		}
	}

	return if $tag ne 'ID3';


	my ($major, $minor, $flags) = unpack ("x3CCC", $header);

	$v2h->{version} = sprintf("ID3v2.%d.%d", $major, $minor);
	$v2h->{major_version} = $major;
	$v2h->{minor_version} = $minor;


	my @bits = split(//, unpack('b8', pack('v', $flags)));

	if ($v2h->{major_version} == 2) {
		$v2h->{unsync}       = $bits[7];
		$v2h->{compression}  = $bits[6]; # Should be ignored - no defined form
		$v2h->{ext_header}   = 0;
		$v2h->{experimental} = 0;
	} else {
		$v2h->{unsync}       = $bits[7];
		$v2h->{ext_header}   = $bits[6];
		$v2h->{experimental} = $bits[5];
		$v2h->{footer}       = $bits[4] if $v2h->{major_version} == 4;
	}


	my $rawsize = substr($header, 6, 4);

	for my $b (unpack('C4', $rawsize)) {

		$v2h->{tag_size} = ($v2h->{tag_size} << 7) + $b;
	}

	$v2h->{tag_size} += 10;	# include ID3v2 header size
	$v2h->{tag_size} += 10 if $v2h->{footer};







	$v2h->{ext_header_size} = 0;

	if ($v2h->{ext_header}) {
		my $filesize = -s $fh;

		read $fh, my $bytes, 4;
		my @bytes = reverse unpack 'C4', $bytes;


		my $bytesize = ($v2h->{major_version} > 3) ? 128 : 256;
		for my $i (0..3) {
			$v2h->{ext_header_size} += $bytes[$i] * $bytesize ** $i;
		}




		if (($v2h->{ext_header_size} - 10 ) > -s $fh) {

			return $v2h;
		}


		my $ext_data;
		if ($v2h->{major_version} == 3) {

			read $fh, $bytes, 6 + $v2h->{ext_header_size};
			my @bits = split //, unpack 'b16', substr $bytes, 0, 2;
			$v2h->{crc_present}      = $bits[15];
			my $padding_size;
			for my $i (0..3) {

				if (defined $bytes[2 + $i]) {
					$padding_size += $bytes[2 + $i] * $bytesize ** $i;
				}
			}
			$ext_data = substr $bytes, 6, $v2h->{ext_header_size} - $padding_size;
		}
		elsif ($v2h->{major_version} == 4) {

			read $fh, $bytes, $v2h->{ext_header_size} - 4;
			my @bits = split //, unpack 'b8', substr $bytes, 5, 1;
			$v2h->{update}           = $bits[6];
			$v2h->{crc_present}      = $bits[5];
			$v2h->{tag_restrictions} = $bits[4];
			$ext_data = substr $bytes, 2, $v2h->{ext_header_size} - 6;
		}











	}

	return $v2h;
}




sub _get_v2foot {
	my $fh = $_[0] or return;
	my($v2h, $bytes, @bytes);
	my $eof;

	$eof = tell $fh;


	seek $fh, $eof-10, SEEK_SET; # back 10 bytes for footer
	read $fh, $bytes, 3;

	return undef unless $bytes eq '3DI';


	read $fh, $bytes, 2;
	$v2h->{version} = sprintf "ID3v2.%d.%d",
		@$v2h{qw[major_version minor_version]} =
			unpack 'c2', $bytes;


	read $fh, $bytes, 1;
	my @bits = split //, unpack 'b8', $bytes;
	if ($v2h->{major_version} != 4) {



	} else {
		$v2h->{unsync}       = $bits[7];
		$v2h->{ext_header}   = $bits[6];
		$v2h->{experimental} = $bits[5];
		$v2h->{footer}       = $bits[4];
		if (!$v2h->{footer})
		{





		}
	}


	$v2h->{tag_size} = 10;  # include ID3v2 header size
	$v2h->{tag_size} += 10; # always account for the footer
	read $fh, $bytes, 4;
	@bytes = reverse unpack 'C4', $bytes;
	foreach my $i (0 .. 3) {

		$v2h->{tag_size} += $bytes[$i] * 128 ** $i;
	}





	$v2h->{offset} = $eof - $v2h->{tag_size};


	seek $fh, $v2h->{offset}, 0; # SEEK_SET
	read $fh, $bytes, 3;
	if ($bytes ne "ID3") {



	  return undef;
	}





	return $v2h;
  
};

sub _find_id3_chunk {
	my($fh, $filetype) = @_;
	my($bytes, $size, $tag, $pat, @mat);




	

	if ($filetype eq 'RIF') {  # WAV

		$pat = 'a4V';
		@mat = ('id3 ', 'ID32');
	} elsif ($filetype eq 'FOR') { # AIFF

		$pat = 'a4N';
		@mat = ('ID3 ', 'ID32');
	}
	seek $fh, 12, SEEK_SET;  # skip to the first chunk

	while ((read $fh, $bytes, 8) == 8) {
		($tag, $size)  = unpack $pat, $bytes;
		for my $mat ( @mat ) {
			return 1 if $tag eq $mat;
		}
		seek $fh, $size, SEEK_CUR;
	}

	return 0;
}

sub _unpack_head {
	unpack('l', pack('L', unpack('N', $_[0])));
}

sub _grab_int_16 {
        my $data  = shift;
        my $value = unpack('s', pack('S', unpack('n',substr($$data,0,2))));
        $$data    = substr($$data,2);
        return $value;
}

sub _grab_uint_16 {
        my $data  = shift;
        my $value = unpack('S',substr($$data,0,2));
        $$data    = substr($$data,2);
        return $value;
}

sub _grab_int_32 {
        my $data  = shift;
        my $value = unpack('V',substr($$data,0,4));
        $$data    = substr($$data,4);
        return $value;
}




sub _parse_lyrics3_tag {
	my ($fh, $filesize, $info) = @_;


	seek($fh, (0 - 128 - 9 - 6), SEEK_END);
	read($fh, my $lyrics3_id3v1, 128 + 9 + 6);

	my $lyrics3_lsz = substr($lyrics3_id3v1,  0,   6); # Lyrics3size
	my $lyrics3_end = substr($lyrics3_id3v1,  6,   9); # LYRICSEND or LYRICS200
	my $id3v1_tag   = substr($lyrics3_id3v1, 15, 128); # ID3v1

	my ($lyrics3_size, $lyrics3_offset, $lyrics3_version);


	if ($lyrics3_end eq 'LYRICSEND') {

		$lyrics3_size    = 5100;
		$lyrics3_offset  = $filesize - 128 - $lyrics3_size;
		$lyrics3_version = 1;

	} elsif ($lyrics3_end eq 'LYRICS200') {



		$lyrics3_size    = $lyrics3_lsz + 6 + length('LYRICS200');
		$lyrics3_offset  = $filesize - 128 - $lyrics3_size;
		$lyrics3_version = 2;

	} elsif (substr(reverse($lyrics3_id3v1), 0, 9) eq 'DNESCIRYL') {


		$lyrics3_size    = 5100;
		$lyrics3_offset  = $filesize - $lyrics3_size;
		$lyrics3_version = 1;
		$lyrics3_offset  = $filesize - $lyrics3_size;

	} elsif (substr(reverse($lyrics3_id3v1), 0, 9) eq '002SCIRYL') {



		$lyrics3_size    = reverse(substr(reverse($lyrics3_id3v1), 9, 6)) + 15;
		$lyrics3_offset  = $filesize - $lyrics3_size;
		$lyrics3_version = 2;
	}

	return $lyrics3_offset;
}

sub _close {
	my($file, $fh) = @_;
	unless (ref $file) { # filehandle not passed
		close $fh or carp "Problem closing '$file': $!";
	}
}

BEGIN {
	@mp3_genres = (
		'Blues',
		'Classic Rock',
		'Country',
		'Dance',
		'Disco',
		'Funk',
		'Grunge',
		'Hip-Hop',
		'Jazz',
		'Metal',
		'New Age',
		'Oldies',
		'Other',
		'Pop',
		'R&B',
		'Rap',
		'Reggae',
		'Rock',
		'Techno',
		'Industrial',
		'Alternative',
		'Ska',
		'Death Metal',
		'Pranks',
		'Soundtrack',
		'Euro-Techno',
		'Ambient',
		'Trip-Hop',
		'Vocal',
		'Jazz+Funk',
		'Fusion',
		'Trance',
		'Classical',
		'Instrumental',
		'Acid',
		'House',
		'Game',
		'Sound Clip',
		'Gospel',
		'Noise',
		'AlternRock',
		'Bass',
		'Soul',
		'Punk',
		'Space',
		'Meditative',
		'Instrumental Pop',
		'Instrumental Rock',
		'Ethnic',
		'Gothic',
		'Darkwave',
		'Techno-Industrial',
		'Electronic',
		'Pop-Folk',
		'Eurodance',
		'Dream',
		'Southern Rock',
		'Comedy',
		'Cult',
		'Gangsta',
		'Top 40',
		'Christian Rap',
		'Pop/Funk',
		'Jungle',
		'Native American',
		'Cabaret',
		'New Wave',
		'Psychadelic',
		'Rave',
		'Showtunes',
		'Trailer',
		'Lo-Fi',
		'Tribal',
		'Acid Punk',
		'Acid Jazz',
		'Polka',
		'Retro',
		'Musical',
		'Rock & Roll',
		'Hard Rock',
	);

	@winamp_genres = (
		@mp3_genres,
		'Folk',
		'Folk-Rock',
		'National Folk',
		'Swing',
		'Fast Fusion',
		'Bebop',
		'Latin',
		'Revival',
		'Celtic',
		'Bluegrass',
		'Avantgarde',
		'Gothic Rock',
		'Progressive Rock',
		'Psychedelic Rock',
		'Symphonic Rock',
		'Slow Rock',
		'Big Band',
		'Chorus',
		'Easy Listening',
		'Acoustic',
		'Humour',
		'Speech',
		'Chanson',
		'Opera',
		'Chamber Music',
		'Sonata',
		'Symphony',
		'Booty Bass',
		'Primus',
		'Porn Groove',
		'Satire',
		'Slow Jam',
		'Club',
		'Tango',
		'Samba',
		'Folklore',
		'Ballad',
		'Power Ballad',
		'Rhythmic Soul',
		'Freestyle',
		'Duet',
		'Punk Rock',
		'Drum Solo',
		'Acapella',
		'Euro-House',
		'Dance Hall',
		'Goa',
		'Drum & Bass',
		'Club-House',
		'Hardcore',
		'Terror',
		'Indie',
		'BritPop',
		'Negerpunk',
		'Polsk Punk',
		'Beat',
		'Christian Gangsta Rap',
		'Heavy Metal',
		'Black Metal',
		'Crossover',
		'Contemporary Christian',
		'Christian Rock',
		'Merengue',
		'Salsa',
		'Thrash Metal',
		'Anime',
		'JPop',
		'Synthpop',
	);

	@t_bitrate = ([
		[0, 32, 48, 56,  64,  80,  96, 112, 128, 144, 160, 176, 192, 224, 256],
		[0,  8, 16, 24,  32,  40,  48,  56,  64,  80,  96, 112, 128, 144, 160],
		[0,  8, 16, 24,  32,  40,  48,  56,  64,  80,  96, 112, 128, 144, 160]
	],[
		[0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
		[0, 32, 48, 56,  64,  80,  96, 112, 128, 160, 192, 224, 256, 320, 384],
		[0, 32, 40, 48,  56,  64,  80,  96, 112, 128, 160, 192, 224, 256, 320]
	]);

	@t_sampling_freq = (
		[11025, 12000,  8000],
		[undef, undef, undef],	# reserved
		[22050, 24000, 16000],
		[44100, 48000, 32000]
	);

	@frequency_tbl = map { $_ ? eval "${_}e-3" : 0 }
		map { @$_ } @t_sampling_freq;

	@mp3_info_fields = qw(
		VERSION
		LAYER
		STEREO
		VBR
		BITRATE
		FREQUENCY
		SIZE
		OFFSET
		SECS
		MM
		SS
		MS
		TIME
		COPYRIGHT
		PADDING
		MODE
		FRAMES
		FRAME_LENGTH
		VBR_SCALE
	);

	%rva2_channel_types = (
		0x00 => 'OTHER',
		0x01 => 'MASTER',
		0x02 => 'FRONT_RIGHT',
		0x03 => 'FRONT_LEFT',
		0x04 => 'BACK_RIGHT',
		0x05 => 'BACK_LEFT',
		0x06 => 'FRONT_CENTER',
		0x07 => 'BACK_CENTER',
		0x08 => 'SUBWOOFER',
	);

	%v1_tag_fields =
		(TITLE => 30, ARTIST => 30, ALBUM => 30, COMMENT => 30, YEAR => 4);

	@v1_tag_names = qw(TITLE ARTIST ALBUM YEAR COMMENT TRACKNUM GENRE);

	%v2_to_v1_names = (

		'TT2' => 'TITLE',
		'TP1' => 'ARTIST',
		'TAL' => 'ALBUM',
		'TYE' => 'YEAR',
		'COM' => 'COMMENT',
		'TRK' => 'TRACKNUM',
		'TCO' => 'GENRE', # not clean mapping, but ...

		'TIT2' => 'TITLE',
		'TPE1' => 'ARTIST',
		'TALB' => 'ALBUM',
		'TYER' => 'YEAR',
		'COMM' => 'COMMENT',
		'TRCK' => 'TRACKNUM',
		'TCON' => 'GENRE',

		'UFID' => 'Unique file identifier',
		'TXXX' => 'User defined text information frame',
	);

	%v2_tag_names = (


	);
}

1;
