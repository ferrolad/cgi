package JSON::Any;

use warnings;
use strict;
use Carp qw(croak carp);

=head1 NAME

JSON::Any - Wrapper Class for the various JSON classes.

=head1 VERSION

Version 1.22

=cut

our $VERSION = '1.22';

our $UTF8;

my ( %conf, $handler, $encoder, $decoder );
use constant HANDLER => 0;
use constant ENCODER => 1;
use constant DECODER => 2;
use constant UTF8    => 3;

BEGIN {
    %conf = (
        json => {
            encoder       => 'encode_json',
            decoder       => 'decode_json',
            get_true      => sub { return JSON::true(); },
            get_false     => sub { return JSON::false(); },
            create_object => sub {
                JSON->import( '-support_by_pp', '-no_export' );
                my ( $self, $conf ) = @_;
                my @params = qw(
                    ascii
                    latin1
                    utf8
                    pretty
                    indent
                    space_before
                    space_after
                    relaxed
                    canonical
                    allow_nonref
                    allow_blessed
                    convert_blessed
                    filter_json_object
                    shrink
                    max_depth
                    max_size
                    loose
                    allow_bignum
                    allow_barekey
                    allow_singlequote
                    escape_slash
                    indent_length
                    sort_by
                );
                local $conf->{utf8} = !$conf->{utf8};  # it means the opposite
                my $obj = $handler->new;

                for my $mutator (@params) {
                    next unless exists $conf->{$mutator};
                    $obj = $obj->$mutator( $conf->{$mutator} );
                }

                $self->[ENCODER] = 'encode';
                $self->[DECODER] = 'decode';
                $self->[HANDLER] = $obj;
            },
        },
        json_dwiw => {
            encoder       => 'to_json',
            decoder       => 'from_json',
            get_true      => sub { return JSON::DWIW->true; },
            get_false     => sub { return JSON::DWIW->false; },
            create_object => sub {
                my ( $self, $conf ) = @_;
                my @params = qw(bare_keys);
                croak "JSON::DWIW does not support utf8" if $conf->{utf8};
                $self->[ENCODER] = 'to_json';
                $self->[DECODER] = 'from_json';
                $self->[HANDLER]
                    = $handler->new( { map { $_ => $conf->{$_} } @params } );
            },
        },
        json_xs_1 => {
            encoder       => 'to_json',
            decoder       => 'from_json',
            get_true      => sub { return \1; },
            get_false     => sub { return \0; },
            create_object => sub {
                my ( $self, $conf ) = @_;

                my @params = qw(
                    ascii
                    utf8
                    pretty
                    indent
                    space_before
                    space_after
                    canonical
                    allow_nonref
                    shrink
                    max_depth
                );

                my $obj = $handler->new;
                for my $mutator (@params) {
                    next unless exists $conf->{$mutator};
                    $obj = $obj->$mutator( $conf->{$mutator} );
                }
                $self->[ENCODER] = 'encode';
                $self->[DECODER] = 'decode';
                $self->[HANDLER] = $obj;
            },
        },
        json_xs_2 => {
            encoder       => 'encode_json',
            decoder       => 'decode_json',
            get_true      => sub { return JSON::XS::true(); },
            get_false     => sub { return JSON::XS::false(); },
            create_object => sub {
                my ( $self, $conf ) = @_;

                my @params = qw(
                    ascii
                    latin1
                    utf8
                    pretty
                    indent
                    space_before
                    space_after
                    relaxed
                    canonical
                    allow_nonref
                    allow_blessed
                    convert_blessed
                    filter_json_object
                    shrink
                    max_depth
                    max_size
                );

                local $conf->{utf8} = !$conf->{utf8};  # it means the opposite

                my $obj = $handler->new;
                for my $mutator (@params) {
                    next unless exists $conf->{$mutator};
                    $obj = $obj->$mutator( $conf->{$mutator} );
                }
                $self->[ENCODER] = 'encode';
                $self->[DECODER] = 'decode';
                $self->[HANDLER] = $obj;
            },
        },
        json_syck => {
            encoder  => 'Dump',
            decoder  => 'Load',
            get_true => sub {
                croak "JSON::Syck does not support special boolean values";
            },
            get_false => sub {
                croak "JSON::Syck does not support special boolean values";
            },
            create_object => sub {
                my ( $self, $conf ) = @_;
                croak "JSON::Syck does not support utf8" if $conf->{utf8};
                $self->[ENCODER] = sub { Dump(@_) };
                $self->[DECODER] = sub { Load(@_) };
                $self->[HANDLER] = 'JSON::Syck';
                }
        },
    );
}

sub _make_key {
    my $handler = shift;
    ( my $key = lc($handler) ) =~ s/::/_/g;
    if ( 'json_xs' eq $key ) {
        no strict 'refs';
        $key .= "_" . ( split /\./, ${"$handler\::VERSION"} )[0];
    }
    return $key;
}

my @default    = qw(XS JSON DWIW);
my @deprecated = qw(Syck);

sub _try_loading {
    my @order = @_;
    ( $handler, $encoder, $decoder ) = ();
    foreach my $testmod (@order) {
        $testmod = "JSON::$testmod" unless $testmod eq "JSON";
        eval "require $testmod";
        unless ($@) {
            $handler = $testmod;
            my $key = _make_key($handler);
            $encoder = $conf{$key}->{encoder};
            $decoder = $conf{$key}->{decoder};
            last;
        }
    }
    return ( $handler, $encoder, $decoder );
}

sub import {
    my $class = shift;
    my @order = @_;

    ( $handler, $encoder, $decoder ) = ();

    @order = split /\s/, $ENV{JSON_ANY_ORDER}
        if !@order and $ENV{JSON_ANY_ORDER};

    if (@order) {
        ( $handler, $encoder, $decoder ) = _try_loading(@order);
        if ( $handler && grep { "JSON::$_" eq $handler } @deprecated ) {
            my $last = pop @default;
            carp "Found deprecated package $handler. Please upgrade to ",
                join ', ' => @default, "or $last";
        }
    }
    else {
        ( $handler, $encoder, $decoder ) = _try_loading(@default);
        unless ($handler) {
            ( $handler, $encoder, $decoder ) = _try_loading(@deprecated);
            if ($handler) {
                my $last = pop @default;
                carp "Found deprecated package $handler. Please upgrade to ",
                    join ', ' => @default, "or $last";
            }
        }
    }
    unless ($handler) {
        my $last = pop @default;
        croak "Couldn't find a JSON package. Need ", join ', ' => @default,
            "or $last";
    }
    croak "Couldn't find a decoder method." unless $decoder;
    croak "Couldn't find a encoder method." unless $encoder;
}


sub new {
    my $class = shift;
    my $self  = bless [], $class;
    my $key   = _make_key($handler);
    if ( my $creator = $conf{$key}->{create_object} ) {
        my @config = @_;
        if ( $ENV{JSON_ANY_CONFIG} ) {
            push @config, map { split /=/, $_ } split /,\s*/,
                $ENV{JSON_ANY_CONFIG};
        }
        $creator->( $self, my $conf = {@config} );
        $self->[UTF8] = $conf->{utf8};
    }
    return $self;
}


sub handlerType {
    my $class = shift;
    $handler;
}

sub handler {
    my $self = shift;
    if ( ref $self ) {
        return $self->[HANDLER];
    }
    return $handler;
}


sub true {
    my $key = _make_key($handler);
    return $conf{$key}->{get_true}->();
}


sub false {
    my $key = _make_key($handler);
    return $conf{$key}->{get_false}->();
}

sub objToJson {
    my $self = shift;
    my $obj  = shift;
    croak 'must provide object to convert' unless defined $obj;

    my $json;

    if ( ref $self ) {
        my $method;
        unless ( ref $self->[ENCODER] ) {
            croak "No $handler Object created!"
                unless exists $self->[HANDLER];
            $method = $self->[HANDLER]->can( $self->[ENCODER] );
            croak "$handler can't execute $self->[ENCODER]" unless $method;
        }
        else {
            $method = $self->[ENCODER];
        }
        $json = $self->[HANDLER]->$method($obj);
    }
    else {
        $json = $handler->can($encoder)->($obj);
    }

    utf8::decode($json)
        if ( ref $self ? $self->[UTF8] : $UTF8 )
        and !utf8::is_utf8($json)
        and utf8::valid($json);
    return $json;
}


*to_json = \&objToJson;
*Dump    = \&objToJson;
*encode  = \&objToJson;


sub jsonToObj {
    my $self = shift;
    my $obj  = shift;
    croak 'must provide json to convert' unless defined $obj;

    # some handlers can't parse single booleans (I'm looking at you DWIW)
    if ( $obj =~ /^(true|false)$/ ) {
        return $self->$1;
    }

    if ( ref $self ) {
        my $method;
        unless ( ref $self->[DECODER] ) {
            croak "No $handler Object created!"
                unless exists $self->[HANDLER];
            $method = $self->[HANDLER]->can( $self->[DECODER] );
            croak "$handler can't execute $self->[DECODER]" unless $method;
        }
        else {
            $method = $self->[DECODER];
        }
        return $self->[HANDLER]->$method($obj);
    }
    $handler->can($decoder)->($obj);
}


*from_json = \&jsonToObj;
*Load      = \&jsonToObj;
*decode    = \&jsonToObj;

1;
