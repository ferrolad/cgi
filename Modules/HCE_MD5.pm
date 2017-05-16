package HCE_MD5;
use Digest::MD5;
use MIME::Base64;

sub new {
    my $class = shift;
    my $self = {};
 
    bless $self, $class;
 
    if ((scalar(@_) != 2) && (scalar(@_ != 3))) {
        die"Error: must be invoked HCE_MD5->new(key, random_thing) or HCE_MD5->new(KEYBUG, key, random_thing)";
    }
    if ($_[0] eq "KEYBUG") {
	$self->{HAVE_KEYBUG} = shift(@_);
    } else {
	delete $self->{HAVE_KEYBUG};
    }
    $self->{SKEY} = shift(@_);
    $self->{RKEY} = shift(@_);
 
    return $self;
}
 
sub _new_key {
    my $self = shift;
    my ($rnd) = @_;
 
    my $context = new Digest::MD5;
    $context->add($self->{SKEY}, $rnd);
    my $digest = $context->digest();
    my @e_block = unpack('C*', $digest);
    return @e_block;
}
 
sub hce_block_encrypt {
    my $self = shift;
    my ($data) = @_;
    my ($i, $key, $data_size, $ans, $mod, @e_block, @data, @key, @ans);
 
    @key = unpack ('C*', $self->{SKEY});
    @data = unpack ('C*', $data);
    
    undef @ans;
    @e_block = $self->_new_key($self->{RKEY});
    $data_size = scalar(@data);
    for($i=0; $i < $data_size; $i++) {
        $mod = $i % 16;
        if (($mod == 0) && ($i > 15)) {
	    if (defined($self->{HAVE_KEYBUG})) {
		@e_block = $self->_new_key((@ans)[($i-16)..($i-1)]);
	    } else {
		@e_block = $self->_new_key(pack 'C*', (@ans)[($i-16)..($i-1)]);
	    }
        }
        $ans[$i] = $e_block[$mod] ^ $data[$i];
    }
    $ans = pack 'C*', @ans;
    return $ans;
}

sub hce_block_decrypt {
    my $self = shift;
    my ($data) = @_;
    my ($i, $key, $data_size, $ans, $mod, @e_block, @data, @key, @ans);
 
    @key = unpack ('C*', $self->{SKEY});
    @data = unpack ('C*', $data);
    
    undef @ans;
    @e_block = $self->_new_key($self->{RKEY});
    $data_size = scalar(@data);
    for($i=0; $i < $data_size; $i++) {
        $mod = $i % 16;
        if (($mod == 0) && ($i > 15)) {
	    if (defined($self->{HAVE_KEYBUG})) {
		@e_block = $self->_new_key((@data)[($i-16)..($i-1)]);
	    } else {
		@e_block = $self->_new_key(pack 'C*', (@data)[($i-16)..($i-1)]);
	    }
        }
        $ans[$i] = $e_block[$mod] ^ $data[$i];
    }
    $ans = pack 'C*', @ans;
    return $ans;
}

sub hce_block_encode_mime {
    my $self = shift;
    my ($data) = @_;
    
    my $new_data = $self->hce_block_encrypt($data);
    my $encode = encode_base64($new_data, "");
    return $encode;
}
 
sub hce_block_decode_mime {
    my $self = shift;
    my ($data) = @_;
    
    my $decode = decode_base64($data);
    my $new_data = $self->hce_block_decrypt($decode);
    return $new_data;
}


1;
