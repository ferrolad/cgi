package JSON;


use strict;
use Carp ();
use base qw(Exporter);
@JSON::EXPORT = qw(from_json to_json jsonToObj objToJson encode_json decode_json);

BEGIN {
    $JSON::VERSION = '2.17';
    $JSON::DEBUG   = 0 unless (defined $JSON::DEBUG);
}

my $Module_XS  = 'JSON::XS';
my $Module_PP  = 'JSON::PP';
my $XS_Version = '2.27';


# XS and PP common methods

my @PublicMethods = qw/
    ascii latin1 utf8 pretty indent space_before space_after relaxed canonical allow_nonref 
    allow_blessed convert_blessed filter_json_object filter_json_single_key_object 
    shrink max_depth max_size encode decode decode_prefix allow_unknown
/;

my @Properties = qw/
    ascii latin1 utf8 indent space_before space_after relaxed canonical allow_nonref
    allow_blessed convert_blessed shrink max_depth max_size allow_unknown
/;

my @XSOnlyMethods = qw//; # Currently nothing

my @PPOnlyMethods = qw/
    indent_length sort_by
    allow_singlequote allow_bignum loose allow_barekey escape_slash as_nonblessed
/; # JSON::PP specific


my $_INSTALL_DONT_DIE  = 1; # When _load_xs fails to load XS, don't die.
my $_INSTALL_ONLY      = 2; # Don't call _set_methods()
my $_ALLOW_UNSUPPORTED = 0;
my $_UNIV_CONV_BLESSED = 0;


unless ($JSON::Backend) {
    $JSON::DEBUG and  Carp::carp("Check used worker module...");

    my $backend = exists $ENV{PERL_JSON_BACKEND} ? $ENV{PERL_JSON_BACKEND} : 1;

    if ($backend eq '1' or $backend =~ /JSON::XS\s*,\s*JSON::PP/) {
        _load_xs($_INSTALL_DONT_DIE) or _load_pp();
    }
    elsif ($backend eq '0' or $backend eq 'JSON::PP') {
        _load_pp();
    }
    elsif ($backend eq '2' or $backend eq 'JSON::XS') {
        _load_xs();
    }
    else {
        Carp::croak "The value of environmental variable 'PERL_JSON_BACKEND' is invalid.";
    }
}


sub import {
    my $pkg = shift;
    my @what_to_export;
    my $no_export;

    for my $tag (@_) {
        if ($tag eq '-support_by_pp') {
            if (!$_ALLOW_UNSUPPORTED++) {
                JSON::Backend::XS
                    ->support_by_pp(@PPOnlyMethods) if ($JSON::Backend eq $Module_XS);
            }
            next;
        }
        elsif ($tag eq '-no_export') {
            $no_export++, next;
        }
        elsif ( $tag eq '-convert_blessed_universally' ) {
            eval q|
                require B;
                *UNIVERSAL::TO_JSON = sub {
                    my $b_obj = B::svref_2object( $_[0] );
                    return    $b_obj->isa('B::HV') ? { %{ $_[0] } }
                            : $b_obj->isa('B::AV') ? [ @{ $_[0] } ]
                            : undef
                            ;
                }
            | if ( !$_UNIV_CONV_BLESSED++ );
            next;
        }
        push @what_to_export, $tag;
    }

    return if ($no_export);

    __PACKAGE__->export_to_level(1, $pkg, @what_to_export);
}


# OBSOLETED

sub jsonToObj {
    my $alternative = 'from_json';
    if (defined $_[0] and UNIVERSAL::isa($_[0], 'JSON')) {
        shift @_; $alternative = 'decode';
    }
    Carp::carp "'jsonToObj' will be obsoleted. Please use '$alternative' instead.";
    return JSON::from_json(@_);
};

sub objToJson {
    my $alternative = 'to_json';
    if (defined $_[0] and UNIVERSAL::isa($_[0], 'JSON')) {
        shift @_; $alternative = 'encode';
    }
    Carp::carp "'objToJson' will be obsoleted. Please use '$alternative' instead.";
    JSON::to_json(@_);
};


# INTERFACES

sub to_json ($@) {
    my $json = new JSON;

    if (@_ == 2 and ref $_[1] eq 'HASH') {
        my $opt  = $_[1];
        for my $method (keys %$opt) {
            $json->$method( $opt->{$method} );
        }
    }

    $json->encode($_[0]);
}


sub from_json ($@) {
    my $json = new JSON;

    if (@_ == 2 and ref $_[1] eq 'HASH') {
        my $opt  = $_[1];
        for my $method (keys %$opt) {
            $json->$method( $opt->{$method} );
        }
    }

    return $json->decode( $_[0] );
}


sub true  { $JSON::true  }

sub false { $JSON::false }

sub null  { undef; }


sub require_xs_version { $XS_Version; }

sub backend {
    my $proto = shift;
    $JSON::Backend;
}

#*module = *backend;


sub is_xs {
    return $_[0]->module eq $Module_XS;
}


sub is_pp {
    return $_[0]->module eq $Module_PP;
}


sub pureperl_only_methods { @PPOnlyMethods; }


sub property {
    my ($self, $name, $value) = @_;

    if (@_ == 1) {
        my %props;
        for $name (@Properties) {
            my $method = 'get_' . $name;
            if ($name eq 'max_size') {
                my $value = $self->$method();
                $props{$name} = $value == 1 ? 0 : $value;
                next;
            }
            $props{$name} = $self->$method();
        }
        return \%props;
    }
    elsif (@_ > 3) {
        Carp::croak('property() can take only the option within 2 arguments.');
    }
    elsif (@_ == 2) {
        if ( my $method = $self->can('get_' . $name) ) {
            if ($name eq 'max_size') {
                my $value = $self->$method();
                return $value == 1 ? 0 : $value;
            }
            $self->$method();
        }
    }
    else {
        $self->$name($value);
    }

}



# INTERNAL

sub _load_xs {
    my $opt = shift;

    $JSON::DEBUG and Carp::carp "Load $Module_XS.";

    # if called after install module, overload is disable.... why?
    JSON::Boolean::_overrride_overload($Module_XS);
    JSON::Boolean::_overrride_overload($Module_PP);

    eval qq|
        use $Module_XS $XS_Version ();
    |;

    if ($@) {
        if (defined $opt and $opt & $_INSTALL_DONT_DIE) {
            $JSON::DEBUG and Carp::carp "Can't load $Module_XS...($@)";
            return 0;
        }
        Carp::croak $@;
    }

    unless (defined $opt and $opt & $_INSTALL_ONLY) {
        _set_module( $JSON::Backend = $Module_XS );
        my $data = join("", <DATA>); # this code is from Jcode 2.xx.
        close(DATA);
        eval $data;
        JSON::Backend::XS->init;
    }

    return 1;
};


sub _load_pp {
    my $opt = shift;

    $JSON::DEBUG and Carp::carp "Load $Module_PP.";

    JSON::Boolean::_overrride_overload($Module_XS);
    JSON::Boolean::_overrride_overload($Module_PP);

    eval qq| require $Module_PP |;
    if ($@) {
        Carp::croak $@;
    }

    unless (defined $opt and $opt & $_INSTALL_ONLY) {
        _set_module( $JSON::Backend = $Module_PP );
        JSON::Backend::PP->init;
    }
};


sub _set_module {
    my $module = shift;

    local $^W;
    no strict qw(refs);

    $JSON::true  = ${"$module\::true"};
    $JSON::false = ${"$module\::false"};

    push @JSON::ISA, $module;
    push @{"$module\::Boolean::ISA"}, qw(JSON::Boolean);

    *{"JSON::is_bool"} = \&{"$module\::is_bool"};

    for my $method ($module eq $Module_XS ? @PPOnlyMethods : @XSOnlyMethods) {
        *{"JSON::$method"} = sub {
            Carp::carp("$method is not supported in $module.");
            $_[0];
        };
    }

    return 1;
}



#
# JSON Boolean
#

package JSON::Boolean;

my %Installed;

sub _overrride_overload {
    return if ($Installed{ $_[0] }++);

    my $boolean = $_[0] . '::Boolean';

    eval sprintf(q|
        package %s;
        use overload (
            '""' => sub { ${$_[0]} == 1 ? 'true' : 'false' },
            'eq' => sub {
                my ($obj, $op) = ref ($_[0]) ? ($_[0], $_[1]) : ($_[1], $_[0]);
                if ($op eq 'true' or $op eq 'false') {
                    return "$obj" eq 'true' ? 'true' eq $op : 'false' eq $op;
                }
                else {
                    return $obj ? 1 == $op : 0 == $op;
                }
            },
        );
    |, $boolean);

    if ($@) { Carp::croak $@; }

    return 1;
}


package JSON::Backend::PP;

sub init {
    local $^W;
    no strict qw(refs);
    *{"JSON::decode_json"} = \&{"JSON::PP::decode_json"};
    *{"JSON::encode_json"} = \&{"JSON::PP::encode_json"};
    *{"JSON::PP::is_xs"}  = sub { 0 };
    *{"JSON::PP::is_pp"}  = sub { 1 };
    return 1;
}

package JSON;

1;
__DATA__



package JSON::Backend::XS;

use constant INDENT_LENGTH_FLAG => 15 << 12;

use constant UNSUPPORTED_ENCODE_FLAG => {
    ESCAPE_SLASH      => 0x00000010,
    ALLOW_BIGNUM      => 0x00000020,
    AS_NONBLESSED     => 0x00000040,
    EXPANDED          => 0x10000000, # for developer's
};

use constant UNSUPPORTED_DECODE_FLAG => {
    LOOSE             => 0x00000001,
    ALLOW_BIGNUM      => 0x00000002,
    ALLOW_BAREKEY     => 0x00000004,
    ALLOW_SINGLEQUOTE => 0x00000008,
    EXPANDED          => 0x20000000, # for developer's
};


sub init {
    local $^W;
    no strict qw(refs);
    *{"JSON::decode_json"} = \&{"JSON::XS::decode_json"};
    *{"JSON::encode_json"} = \&{"JSON::XS::encode_json"};
    *{"JSON::XS::is_xs"}  = sub { 1 };
    *{"JSON::XS::is_pp"}  = sub { 0 };
    return 1;
}


sub support_by_pp {
    my ($class, @methods) = @_;

    local $^W;
    no strict qw(refs);

    push @JSON::Backend::XS::Supportable::ISA, 'JSON';

    my $pkg = 'JSON::Backend::XS::Supportable';

    *{JSON::new} = sub {
        my $proto = new JSON::XS; $$proto = 0;
        bless  $proto, $pkg;
    };


    for my $method (@methods) {
        my $flag = uc($method);
        my $type |= (UNSUPPORTED_ENCODE_FLAG->{$flag} || 0);
           $type |= (UNSUPPORTED_DECODE_FLAG->{$flag} || 0);

        next unless($type);

        $pkg->_make_unsupported_method($method => $type);
    }

    push @{"JSON::XS::Boolean::ISA"}, qw(JSON::PP::Boolean);
    push @{"JSON::PP::Boolean::ISA"}, qw(JSON::Boolean);

    $JSON::DEBUG and Carp::carp("set -support_by_pp mode.");

    return 1;
}




#
# Helper classes for XS
#

package JSON::Backend::XS::Supportable;

{
    my $JSON_XS_encode_orignal = \&JSON::XS::encode;
    my $JSON_XS_decode_orignal = \&JSON::XS::decode;
    my $JSON_XS_incr_parse_orignal = \&JSON::XS::incr_parse;

    local $^W;
    *JSON::XS::decode = \&JSON::Backend::XS::Supportable::_decode;
    *JSON::XS::encode = \&JSON::Backend::XS::Supportable::_encode;
    *JSON::XS::incr_parse = \&JSON::Backend::XS::Supportable::_incr_parse;

    *{JSON::XS::_original_decode} = $JSON_XS_decode_orignal;
    *{JSON::XS::_original_encode} = $JSON_XS_encode_orignal;
    *{JSON::XS::_original_incr_parse} = $JSON_XS_incr_parse_orignal;
}

$Carp::Internal{'JSON::Backend::XS::Supportable'} = 1;

sub _make_unsupported_method {
    my ($pkg, $method, $type) = @_;

    local $^W;
    no strict qw(refs);

    *{"$pkg\::$method"} = sub {
        local $^W;
        if (defined $_[1] ? $_[1] : 1) {
            ${$_[0]} |= $type;
        }
        else {
            ${$_[0]} &= ~$type;
        }
        $_[0];
    };

    *{"$pkg\::get_$method"} = sub {
        ${$_[0]} & $type ? 1 : '';
    };

}


sub _set_for_pp {
    require JSON::PP;
    my $type  = shift;
    my $pp    = new JSON::PP;
    my $prop = $_[0]->property;

    for my $name (keys %$prop) {
        $pp->$name( $prop->{$name} ? $prop->{$name} : 0 );
    }

    my $unsupported = $type eq 'encode' ? JSON::Backend::XS::UNSUPPORTED_ENCODE_FLAG
                                        : JSON::Backend::XS::UNSUPPORTED_DECODE_FLAG;
    my $flags       = ${$_[0]} || 0;

    for my $name (keys %$unsupported) {
        next if ($name eq 'EXPANDED'); # for developer's
        my $enable = ($flags & $unsupported->{$name}) ? 1 : 0;
        my $method = lc $name;
        $pp->$method($enable);
    }

    $pp->indent_length( $_[0]->get_indent_length );

    return $pp;
}

sub _encode { # using with PP encod
    if (${$_[0]}) {
        _set_for_pp('encode' => @_)->encode($_[1]);
    }
    else {
        $_[0]->_original_encode( $_[1] );
    }
}


sub _decode { # if unsupported-flag is set, use PP
    if (${$_[0]}) {
        _set_for_pp('decode' => @_)->decode($_[1]);
    }
    else {
        $_[0]->_original_decode( $_[1] );
    }
}


sub decode_prefix { # if unsupported-flag is set, use PP
    _set_for_pp('decode' => @_)->decode_prefix($_[1]);
}


sub _incr_parse {
    if (${$_[0]}) {
        _set_for_pp('decode' => @_)->incr_parse($_[1]);
    }
    else {
        $_[0]->_original_incr_parse( $_[1] );
    }
}


sub get_indent_length {
    ${$_[0]} << 4 >> 16;
}


sub indent_length {
    my $length = $_[1];

    if (!defined $length or $length > 15 or $length < 0) {
        Carp::carp "The acceptable range of indent_length() is 0 to 15.";
    }
    else {
        local $^W;
        $length <<= 12;
        ${$_[0]} &= ~ JSON::Backend::XS::INDENT_LENGTH_FLAG;
        ${$_[0]} |= $length;
        *JSON::XS::encode = \&JSON::Backend::XS::Supportable::_encode;
    }

    $_[0];
}


1;
