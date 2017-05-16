package MIME::Lite;


require 5.004;

use Carp();
use FileHandle;

use strict;
use vars qw(
  $AUTO_CC
  $AUTO_CONTENT_TYPE
  $AUTO_ENCODE
  $AUTO_VERIFY
  $PARANOID
  $QUIET
  $VANILLA
  $VERSION
  $DEBUG
);


$VERSION = '3.021';

### Automatically interpret CC/BCC for SMTP:
$AUTO_CC = 1;

### Automatically choose content type from file name:
$AUTO_CONTENT_TYPE = 0;

### Automatically choose encoding from content type:
$AUTO_ENCODE = 1;

### Check paths right before printing:
$AUTO_VERIFY = 1;

### Set this true if you don't want to use MIME::Base64/QuotedPrint/Types:
$PARANOID = 0;

### Don't warn me about dangerous activities:
$QUIET = undef;

### Unsupported (for tester use): don't qualify boundary with time/pid:
$VANILLA = 0;

$MIME::Lite::DEBUG = 0;

#==============================
#==============================
#
# GLOBALS, INTERNAL...

my $Sender = "";
my $SENDMAIL = "";

if ( $^O =~ /win32/i ) {
    $Sender = "smtp";
} else {
    ### Find sendmail:
    $Sender   = "sendmail";
    $SENDMAIL = "/usr/lib/sendmail";
    ( -x $SENDMAIL ) or ( $SENDMAIL = "/usr/sbin/sendmail" );
    ( -x $SENDMAIL ) or ( $SENDMAIL = "sendmail" );
    unless (-x $SENDMAIL) {
        require File::Spec;
        for my $dir (File::Spec->path) {
            if ( -x "$dir/sendmail" ) {
                $SENDMAIL = "$dir/sendmail";
                last;
            }
        }
    }
    unless (-x $SENDMAIL) {
        Carp::croak "can't find an executable sendmail"
    }
}

### Our sending facilities:
my %SenderArgs = (
  sendmail  => ["$SENDMAIL -t -oi -oem"],
  smtp      => [],
  sub       => [],
);

### Boundary counter:
my $BCount = 0;

### Known Mail/MIME fields... these, plus some general forms like
### "x-*", are recognized by build():
my %KnownField = map { $_ => 1 }
  qw(
  bcc         cc          comments      date          encrypted
  from        keywords    message-id    mime-version  organization
  received    references  reply-to      return-path   sender
  subject     to

  approved
);

### What external packages do we use for encoding?
my @Uses;

### Header order:
my @FieldOrder;

### See if we have File::Basename
my $HaveFileBasename = 0;
if ( eval "require File::Basename" ) {    # not affected by $PARANOID, core Perl
    $HaveFileBasename = 1;
    push @Uses, "F$File::Basename::VERSION";
}

### See if we have/want MIME::Types
my $HaveMimeTypes = 0;
if ( !$PARANOID and eval "require MIME::Types; MIME::Types->VERSION(1.004);" ) {
    $HaveMimeTypes = 1;
    push @Uses, "T$MIME::Types::VERSION";
}

sub fold {
    my $str = shift;
    $str =~ s/^\s*|\s*$//g;    ### trim
    $str =~ s/\n/\n /g;
    $str;
}

sub gen_boundary {
    return ( "_----------=_" . ( $VANILLA ? '' : int(time) . $$ ) . $BCount++ );
}


sub is_mime_field {
    $_[0] =~ /^(mime\-|content\-)/i;
}

BEGIN {
    my $ATOM      = '[^ \000-\037()<>@,;:\134"\056\133\135]+';
    my $QSTR      = '".*?"';
    my $WORD      = '(?:' . $QSTR . '|' . $ATOM . ')';
    my $DOMAIN    = '(?:' . $ATOM . '(?:' . '\\.' . $ATOM . ')*' . ')';
    my $LOCALPART = '(?:' . $WORD . '(?:' . '\\.' . $WORD . ')*' . ')';
    my $ADDR      = '(?:' . $LOCALPART . '@' . $DOMAIN . ')';
    my $PHRASE    = '(?:' . $WORD . ')+';
    my $SEP       = "(?:^\\s*|\\s*,\\s*)";                                ### before elems in a list

    sub my_extract_full_addrs {
        my $str = shift;
        my @addrs;
        $str =~ s/\s/ /g;                                                 ### collapse whitespace

        pos($str) = 0;
        while ( $str !~ m{\G\s*\Z}gco ) {
            ### print STDERR "TACKLING: ".substr($str, pos($str))."\n";
            if ( $str =~ m{\G$SEP($PHRASE)\s*<\s*($ADDR)\s*>}gco ) {
                push @addrs, "$1 <$2>";
            } elsif ( $str =~ m{\G$SEP($ADDR)}gco or $str =~ m{\G$SEP($ATOM)}gco ) {
                push @addrs, $1;
            } else {
                my $problem = substr( $str, pos($str) );
                die "can't extract address at <$problem> in <$str>\n";
            }
        }
        return wantarray ? @addrs : $addrs[0];
    }

    sub my_extract_only_addrs {
        my @ret = map { /<([^>]+)>/ ? $1 : $_ } my_extract_full_addrs(@_);
        return wantarray ? @ret : $ret[0];
    }
}
#------------------------------


if ( !$PARANOID and eval "require Mail::Address" ) {
    push @Uses, "A$Mail::Address::VERSION";
    eval q{
                sub extract_full_addrs {
                    my @ret=map { $_->format } Mail::Address->parse($_[0]);
                    return wantarray ? @ret : $ret[0]
                }
                sub extract_only_addrs {
                    my @ret=map { $_->address } Mail::Address->parse($_[0]);
                    return wantarray ? @ret : $ret[0]
                }
    };    ### q
} else {
    eval q{
        *extract_full_addrs=*my_extract_full_addrs;
        *extract_only_addrs=*my_extract_only_addrs;
    };    ### q
}    ### if


if ( !$PARANOID and eval "require MIME::Base64" ) {
    import MIME::Base64 qw(encode_base64);
    push @Uses, "B$MIME::Base64::VERSION";
} else {
    eval q{
        sub encode_base64 {
            my $res = "";
            my $eol = "\n";

            pos($_[0]) = 0;        ### thanks, Andreas!
            while ($_[0] =~ /(.{1,45})/gs) {
            $res .= substr(pack('u', $1), 1);
            chop($res);
            }
            $res =~ tr|` -_|AA-Za-z0-9+/|;

            ### Fix padding at the end:
            my $padding = (3 - length($_[0]) % 3) % 3;
            $res =~ s/.{$padding}$/'=' x $padding/e if $padding;

            ### Break encoded string into lines of no more than 76 characters each:
            $res =~ s/(.{1,76})/$1$eol/g if (length $eol);
            return $res;
        } ### sub
  }    ### q
}    ### if


if ( !$PARANOID and eval "require MIME::QuotedPrint" ) {
    import MIME::QuotedPrint qw(encode_qp);
    push @Uses, "Q$MIME::QuotedPrint::VERSION";
} else {
    eval q{
        sub encode_qp {
            my $res = shift;
            local($_);
            $res =~ s/([^ \t\n!-<>-~])/sprintf("=%02X", ord($1))/eg;  ### rule #2,#3
            $res =~ s/([ \t]+)$/
              join('', map { sprintf("=%02X", ord($_)) }
                       split('', $1)
              )/egm;                        ### rule #3 (encode whitespace at eol)

            ### rule #5 (lines shorter than 76 chars, but can't break =XX escapes:
            my $brokenlines = "";
            $brokenlines .= "$1=\n" while $res =~ s/^(.{70}([^=]{2})?)//; ### 70 was 74
            $brokenlines =~ s/=\n$// unless length $res;
            "$brokenlines$res";
        } ### sub
  }    ### q
}    ### if


sub encode_8bit {
    my $str = shift;
    $str =~ s/^(.{990})/$1\n/mg;
    $str;
}

sub encode_7bit {
    my $str = shift;
    $str =~ s/[\x80-\xFF]//g;
    $str =~ s/^(.{990})/$1\n/mg;
    $str;
}

#==============================
#==============================

=head2 Construction

=over 4

=cut


sub new {
    my $class = shift;

    ### Create basic object:
    my $self = { Attrs    => {},    ### MIME attributes
                 SubAttrs => {},    ### MIME sub-attributes
                 Header   => [],    ### explicit message headers
                 Parts    => [],    ### array of parts
    };
    bless $self, $class;

    ### Build, if needed:
    return ( @_ ? $self->build(@_) : $self );
}


sub attach {
    my $self = shift;
    my $attrs = $self->{Attrs};
    my $sub_attrs = $self->{SubAttrs};

    ### Create new part, if necessary:
    my $part1 = ( ( @_ == 1 ) ? shift: ref($self)->new( Top => 0, @_ ) );

    ### Do the "attach-to-singlepart" hack:
    if ( $attrs->{'content-type'} !~ m{^(multipart|message)/}i ) {

        ### Create part zero:
        my $part0 = ref($self)->new;

        ### Cut MIME stuff from self, and paste into part zero:
        foreach (qw(SubAttrs Attrs Data Path FH)) {
            $part0->{$_} = $self->{$_};
            delete( $self->{$_} );
        }
        $part0->top_level(0);    ### clear top-level attributes

        ### Make self a top-level multipart:
        $attrs = $self->{Attrs} ||= {};       ### reset (sam: bug?  this doesn't reset anything since Attrs is already a hash-ref)
        $sub_attrs = $self->{SubAttrs} ||= {};    ### reset
        $attrs->{'content-type'}              = 'multipart/mixed';
        $sub_attrs->{'content-type'}{'boundary'}      = gen_boundary();
        $attrs->{'content-transfer-encoding'} = '7bit';
        $self->top_level(1);      ### activate top-level attributes

        ### Add part 0:
        push @{ $self->{Parts} }, $part0;
    }

    ### Add the new part:
    push @{ $self->{Parts} }, $part1;
    $part1;
}



sub build {
    my $self   = shift;
    my %params = @_;
    my @params = @_;
    my $key;

    ### Miko's note: reorganized to check for exactly one of Data, Path, or FH
    ( defined( $params{Data} ) + defined( $params{Path} ) + defined( $params{FH} ) <= 1 )
      or Carp::croak "supply exactly zero or one of (Data|Path|FH).\n";

    ### Create new instance, if necessary:
    ref($self) or $self = $self->new;


    ### CONTENT-TYPE....
    ###

    ### Get content-type or content-type-macro:
    my $type = ( $params{Type} || ( $AUTO_CONTENT_TYPE ? 'AUTO' : 'TEXT' ) );

    ### Interpret content-type-macros:
    if    ( $type eq 'TEXT' )   { $type = 'text/plain'; }
    elsif ( $type eq 'HTML' )   { $type = 'text/html'; }
    elsif ( $type eq 'BINARY' ) { $type = 'application/octet-stream' }
    elsif ( $type eq 'AUTO' )   { $type = $self->suggest_type( $params{Path} ); }

    ### We now have a content-type; set it:
    $type = lc($type);
    my $attrs  = $self->{Attrs};
    my $sub_attrs  = $self->{SubAttrs};
    $attrs->{'content-type'} = $type;

    ### Get some basic attributes from the content type:
    my $is_multipart = ( $type =~ m{^(multipart)/}i );

    ### Add in the multipart boundary:
    if ($is_multipart) {
        my $boundary = gen_boundary();
        $sub_attrs->{'content-type'}{'boundary'} = $boundary;
    }


    if ( defined $params{Id} ) {
        my $id = $params{Id};
        $id = "<$id>" unless $id =~ /\A\s*<.*>\s*\z/;
        $attrs->{'content-id'} = $id;
    }


    if ( defined( $params{Data} ) ) {
        $self->data( $params{Data} );
    }
    ### ...or a path to data:
    elsif ( defined( $params{Path} ) ) {
        $self->path( $params{Path} );    ### also sets filename
        $self->read_now if $params{ReadNow};
    }
    ### ...or a filehandle to data:
    ### Miko's note: this part works much like the path routine just above,
    elsif ( defined( $params{FH} ) ) {
        $self->fh( $params{FH} );
        $self->read_now if $params{ReadNow};    ### implement later
    }


    if ( defined( $params{Filename} ) ) {
        $self->filename( $params{Filename} );
    }


    ### CONTENT-TRANSFER-ENCODING...
    ###

    ### Get it:
    my $enc =
      ( $params{Encoding} || ( $AUTO_ENCODE and $self->suggest_encoding($type) ) || 'binary' );
    $attrs->{'content-transfer-encoding'} = lc($enc);

    ### Sanity check:
    if ( $type =~ m{^(multipart|message)/} ) {
        ( $enc =~ m{^(7bit|8bit|binary)\Z} )
          or Carp::croak( "illegal MIME: " . "can't have encoding $enc with type $type\n" );
    }

    ### CONTENT-DISPOSITION...
    ###    Default is inline for single, none for multis:
    ###
    my $disp = ( $params{Disposition} or ( $is_multipart ? undef: 'inline' ) );
    $attrs->{'content-disposition'} = $disp;

    ### CONTENT-LENGTH...
    ###
    my $length;
    if ( exists( $params{Length} ) ) {    ### given by caller:
        $attrs->{'content-length'} = $params{Length};
    } else {                              ### compute it ourselves
        $self->get_length;
    }

    ### Init the top-level fields:
    my $is_top = defined( $params{Top} ) ? $params{Top} : 1;
    $self->top_level($is_top);

    ### Datestamp if desired:
    my $ds_wanted = $params{Datestamp};
    my $ds_defaulted = ( $is_top and !exists( $params{Datestamp} ) );
    if ( ( $ds_wanted or $ds_defaulted ) and !exists( $params{Date} ) ) {
        #require Email::Date::Format;
        #$self->add( "date", Email::Date::Format::email_date() );
    }

    ### Set message headers:
    my @paramz = @params;
    my $field;
    while (@paramz) {
        my ( $tag, $value ) = ( shift(@paramz), shift(@paramz) );
        my $lc_tag = lc($tag);

        ### Get tag, if a tag:
        if ( $lc_tag =~ /^-(.*)/ ) {                   ### old style, backwards-compatibility
            $field = $1;
        } elsif ( $lc_tag =~ /^(.*):$/ ) {             ### new style
            $field = $1;
        } elsif ( $KnownField{$lc_tag} or
                  $lc_tag =~ m{^(content|resent|x)-.} ){
            $field = $lc_tag;
        } else {                                          ### not a field:
            next;
        }

        ### Add it:
        $self->add( $field, $value );
    }

    ### Done!
    $self;
}

=back

=cut


#==============================
#==============================

=head2 Setting/getting headers and attributes

=over 4

=cut


sub top_level {
    my ( $self, $onoff ) = @_;
    my $attrs = $self->{Attrs};
    if ($onoff) {
        $attrs->{'MIME-Version'} = '1.0';
        my $uses = ( @Uses ? ( "(" . join( "; ", @Uses ) . ")" ) : '' );
        $self->replace( 'X-Mailer' => "MIME::Lite $VERSION $uses" )
          unless $VANILLA;
    } else {
        delete $attrs->{'MIME-Version'};
        $self->delete('X-Mailer');
    }
}

sub add {
    my $self  = shift;
    my $tag   = lc(shift);
    my $value = shift;

    ### If a dangerous option, warn them:
    Carp::carp "Explicitly setting a MIME header field ($tag) is dangerous:\n"
      . "use the attr() method instead.\n"
      if ( is_mime_field($tag) && !$QUIET );

    ### Get array of clean values:
    my @vals = ( ( ref($value) and ( ref($value) eq 'ARRAY' ) )
                 ? @{$value}
                 : ( $value . '' )
    );
    map { s/\n/\n /g } @vals;

    ### Add them:
    foreach (@vals) {
        push @{ $self->{Header} }, [ $tag, $_ ];
    }
}

sub attr {
    my ( $self, $attr, $value ) = @_;
    my $attrs = $self->{Attrs};

    $attr = lc($attr);

    ### Break attribute name up:
    my ( $tag, $subtag ) = split /\./, $attr;
    if (defined($subtag)) {
        $attrs = $self->{SubAttrs}{$tag} ||= {};
        $tag   = $subtag;
    }

    ### Set or get?
    if ( @_ > 2 ) {    ### set:
        if ( defined($value) ) {
            $attrs->{$tag} = $value;
        } else {
            delete $attrs->{$tag};
        }
    }

    ### Return current value:
    $attrs->{$tag};
}

sub _safe_attr {
    my ( $self, $attr ) = @_;
    return defined $self->{Attrs}{$attr} ? $self->{Attrs}{$attr} : '';
}


sub delete {
    my $self = shift;
    my $tag  = lc(shift);

    ### Delete from the header:
    my $hdr = [];
    my $field;
    foreach $field ( @{ $self->{Header} } ) {
        push @$hdr, $field if ( $field->[0] ne $tag );
    }
    $self->{Header} = $hdr;
    $self;
}


sub field_order {
    my $self = shift;
    if ( ref($self) ) {
        $self->{FieldOrder} = [ map { lc($_) } @_ ];
    } else {
        @FieldOrder = map { lc($_) } @_;
    }
}


sub fields {
    my $self = shift;
    my @fields;
    my $attrs = $self->{Attrs};
    my $sub_attrs = $self->{SubAttrs};

    ### Get a lookup-hash of all *explicitly-given* fields:
    my %explicit = map { $_->[0] => 1 } @{ $self->{Header} };

    ### Start with any MIME attributes not given explicitly:
    my $tag;
    foreach $tag ( sort keys %{ $self->{Attrs} } ) {

        ### Skip if explicit:
        next if ( $explicit{$tag} );

        # get base attr value or skip if not available
        my $value = $attrs->{$tag};
        defined $value or next;

        ### handle sub-attrs if available
        if (my $subs = $sub_attrs->{$tag}) {
            $value .= '; ' .
              join('; ', map { qq{$_="$subs->{$_}"} } sort keys %$subs);
        }

        # handle stripping \r\n now since we're not doing it in attr()
        # anymore
        $value =~ tr/\r\n//;

        ### Add to running fields;
        push @fields, [ $tag, $value ];
    }

    ### Add remaining fields (note that we duplicate the array for safety):
    foreach ( @{ $self->{Header} } ) {
        push @fields, [ @{$_} ];
    }

    my @order = @{ $self->{FieldOrder} || [] };    ### object-specific
    @order or @order = @FieldOrder;                ### no? maybe generic
    if (@order) {                                  ### either?

        ### Create hash mapping field names to 1-based rank:
        my %rank = map { $order[$_] => ( 1 + $_ ) } ( 0 .. $#order );

        my @ranked = map {
            [ ( $_ + 1000 * ( $rank{ lc( $fields[$_][0] ) } || ( 2 + $#order ) ) ), $fields[$_] ]
        } ( 0 .. $#fields );

        @fields = map { $_->[1] }
          sort { $a->[0] <=> $b->[0] } @ranked;
    }

    ### Done!
    return \@fields;
}


sub filename {
    my ( $self, $filename ) = @_;
    my $sub_attrs = $self->{SubAttrs};

    if ( @_ > 1 ) {
        $sub_attrs->{'content-type'}{'name'} = $filename;
        $sub_attrs->{'content-disposition'}{'filename'} = $filename;
    }
    return $sub_attrs->{'content-disposition'}{'filename'};
}

sub get {
    my ( $self, $tag, $index ) = @_;
    $tag = lc($tag);
    Carp::croak "get: can't be used with MIME fields\n" if is_mime_field($tag);

    my @all = map { ( $_->[0] eq $tag ) ? $_->[1] : () } @{ $self->{Header} };
    ( defined($index) ? $all[$index] : ( wantarray ? @all : $all[0] ) );
}


sub get_length {
    my $self = shift;
    my $attrs = $self->{Attrs};

    my $is_multipart = ( $attrs->{'content-type'} =~ m{^multipart/}i );
    my $enc = lc( $attrs->{'content-transfer-encoding'} || 'binary' );
    my $length;
    if ( !$is_multipart && ( $enc eq "binary" ) ) {    ### might figure it out cheap:
        if ( defined( $self->{Data} ) ) {              ### it's in core
            $length = length( $self->{Data} );
        } elsif ( defined( $self->{FH} ) ) {           ### it's in a filehandle
            ### no-op: it's expensive, so don't bother
        } elsif ( defined( $self->{Path} ) ) {         ### it's a simple file!
            $length = ( -s $self->{Path} ) if ( -e $self->{Path} );
        }
    }
    $attrs->{'content-length'} = $length;
    return $length;
}


sub parts {
    my $self = shift;
    @{ $self->{Parts} || [] };
}

sub preamble {
    my $self = shift;
    $self->{Preamble} = shift if @_;
    $self->{Preamble};
}

sub replace {
    my ( $self, $tag, $value ) = @_;
    $self->delete($tag);
    $self->add( $tag, $value ) if defined($value);
}


sub scrub {
    my ( $self, @a ) = @_;
    my ($expl) = @a;
    local $QUIET = 1;

    ### Scrub me:
    if ( !@a ) {    ### guess

        ### Scrub length always:
        $self->replace( 'content-length', '' );

        ### Scrub disposition if no filename, or if content-type has same info:
        if ( !$self->_safe_attr('content-disposition.filename')
             || $self->_safe_attr('content-type.name') )
        {
            $self->replace( 'content-disposition', '' );
        }

        ### Scrub encoding if effectively unencoded:
        if ( $self->_safe_attr('content-transfer-encoding') =~ /^(7bit|8bit|binary)$/i ) {
            $self->replace( 'content-transfer-encoding', '' );
        }

        ### Scrub charset if US-ASCII:
        if ( $self->_safe_attr('content-type.charset') =~ /^(us-ascii)/i ) {
            $self->attr( 'content-type.charset' => undef );
        }

        ### TBD: this is not really right for message/digest:
        if (     ( keys %{ $self->{Attrs}{'content-type'} } == 1 )
             and ( $self->_safe_attr('content-type') eq 'text/plain' ) )
        {
            $self->replace( 'content-type', '' );
        }
    } elsif ( $expl and ( ref($expl) eq 'ARRAY' ) ) {
        foreach ( @{$expl} ) { $self->replace( $_, '' ); }
    }

    ### Scrub my kids:
    foreach ( @{ $self->{Parts} } ) { $_->scrub(@a); }
}

=back

=cut


#==============================
#==============================

=head2 Setting/getting message data

=over 4

=cut



sub binmode {
    my $self = shift;
    $self->{Binmode} = shift if (@_);    ### argument? set override
    return ( defined( $self->{Binmode} )
             ? $self->{Binmode}
             : ( $self->{Attrs}{"content-type"} !~ m{^(text|message)/}i )
    );
}

sub data {
    my $self = shift;
    if (@_) {
        $self->{Data} = ( ( ref( $_[0] ) eq 'ARRAY' ) ? join( '', @{ $_[0] } ) : $_[0] );
        $self->get_length;
    }
    $self->{Data};
}

sub fh {
    my $self = shift;
    $self->{FH} = shift if @_;
    $self->{FH};
}

sub path {
    my $self = shift;
    if (@_) {

        ### Set the path, and invalidate the content length:
        $self->{Path} = shift;

        ### Re-set filename, extracting it from path if possible:
        my $filename;
        if ( $self->{Path} and ( $self->{Path} !~ /\|$/ ) ) {    ### non-shell path:
            ( $filename = $self->{Path} ) =~ s/^<//;

            ### Consult File::Basename, maybe:
            if ($HaveFileBasename) {
                $filename = File::Basename::basename($filename);
            } else {
                ($filename) = ( $filename =~ m{([^\/]+)\Z} );
            }
        }
        $self->filename($filename);

        ### Reset the length:
        $self->get_length;
    }
    $self->{Path};
}

sub resetfh {
    my $self = shift;
    seek( $self->{FH}, 0, 0 );
}

sub read_now {
    my $self = shift;
    local $/ = undef;

    if ( $self->{FH} ) {    ### data from a filehandle:
        my $chunk;
        my @chunks;
        CORE::binmode( $self->{FH} ) if $self->binmode;
        while ( read( $self->{FH}, $chunk, 1024 ) ) {
            push @chunks, $chunk;
        }
        $self->{Data} = join '', @chunks;
    } elsif ( $self->{Path} ) {    ### data from a path:
        open SLURP, $self->{Path} or Carp::croak "open $self->{Path}: $!\n";
        CORE::binmode(SLURP) if $self->binmode;
        $self->{Data} = <SLURP>;    ### sssssssssssssslurp...
        close SLURP;                ### ...aaaaaaaaahhh!
    }
}

sub sign {
    my $self   = shift;
    my %params = @_;

    ### Default:
    @_ or $params{Path} = "$ENV{HOME}/.signature";

    ### Force message in-core:
    defined( $self->{Data} ) or $self->read_now;

    ### Load signature:
    my $sig;
    if ( !defined( $sig = $params{Data} ) ) {    ### not given explicitly:
        local $/ = undef;
        open SIG, $params{Path} or Carp::croak "open sig $params{Path}: $!\n";
        $sig = <SIG>;                            ### sssssssssssssslurp...
        close SIG;                               ### ...aaaaaaaaahhh!
    }
    $sig = join( '', @$sig ) if ( ref($sig) and ( ref($sig) eq 'ARRAY' ) );

    ### Append, following Internet conventions:
    $self->{Data} .= "\n-- \n$sig";

    ### Re-compute length:
    $self->get_length;
    1;
}

sub suggest_encoding {
    my ( $self, $ctype ) = @_;
    $ctype = lc($ctype);

    ### Consult MIME::Types, maybe:
    if ($HaveMimeTypes) {

        ### Mappings contain [suffix,mimetype,encoding]
        my @mappings = MIME::Types::by_mediatype($ctype);
        if ( scalar(@mappings) ) {
            ### Just pick the first one:
            my ( $suffix, $mimetype, $encoding ) = @{ $mappings[0] };
            if (    $encoding
                 && $encoding =~ /^(base64|binary|[78]bit|quoted-printable)$/i )
            {
                return lc($encoding);    ### sanity check
            }
        }
    }

    ### If we got here, then MIME::Types was no help.
    ### Extract major type:
    my ($type) = split '/', $ctype;
    if ( ( $type eq 'text' ) || ( $type eq 'message' ) ) {    ### scan message body?
        return 'binary';
    } else {
        return ( $type eq 'multipart' ) ? 'binary' : 'base64';
    }
}

sub suggest_type {
    my ( $self, $path ) = @_;

    ### If there's no path, bail:
    $path or return 'application/octet-stream';

    ### Consult MIME::Types, maybe:
    if ($HaveMimeTypes) {

        # Mappings contain [mimetype,encoding]:
        my ( $mimetype, $encoding ) = MIME::Types::by_suffix($path);
        return $mimetype if ( $mimetype && $mimetype =~ /^\S+\/\S+$/ );    ### sanity check
    }

    return 'application/octet-stream';
}

sub verify_data {
    my $self = shift;

    ### Verify self:
    my $path = $self->{Path};
    if ( $path and ( $path !~ /\|$/ ) ) {    ### non-shell path:
        $path =~ s/^<//;
        ( -r $path ) or die "$path: not readable\n";
    }

    ### Verify parts:
    foreach my $part ( @{ $self->{Parts} } ) { $part->verify_data }
    1;
}

=back

=cut




=head2 Output

=over 4

=cut


sub print {
    my ( $self, $out ) = @_;

    ### Coerce into a printable output handle:
    $out = MIME::Lite::IO_Handle->wrap($out);

    ### Output head, separator, and body:
    $self->verify_data if $AUTO_VERIFY;    ### prevents missing parts!
    $out->print( $self->header_as_string, "\n" );
    $self->print_body($out);
}

sub print_for_smtp {
    my ( $self, $out ) = @_;

    ### Coerce into a printable output handle:
    $out = MIME::Lite::IO_Handle->wrap($out);

    ### Create a safe head:
    my @fields = grep { $_->[0] ne 'bcc' } @{ $self->fields };
    my $header = $self->fields_as_string( \@fields );

    ### Output head, separator, and body:
    $out->print( $header, "\n" );
    $self->print_body( $out, '1' );
}


sub print_body {
    my ( $self, $out, $is_smtp ) = @_;
    my $attrs = $self->{Attrs};
    my $sub_attrs = $self->{SubAttrs};

    ### Coerce into a printable output handle:
    $out = MIME::Lite::IO_Handle->wrap($out);

    my $type = $attrs->{'content-type'};
    if ( $type =~ m{^multipart/}i ) {
        my $boundary = $sub_attrs->{'content-type'}{'boundary'};

        ### Preamble:
        $out->print( defined( $self->{Preamble} )
                     ? $self->{Preamble}
                     : "This is a multi-part message in MIME format.\n"
        );

        ### Parts:
        my $part;
        foreach $part ( @{ $self->{Parts} } ) {
            $out->print("\n--$boundary\n");
            $part->print($out);
        }

        ### Epilogue:
        $out->print("\n--$boundary--\n\n");
    } elsif ( $type =~ m{^message/} ) {
        my @parts = @{ $self->{Parts} };

        ### It's a toss-up; try both data and parts:
        if ( @parts == 0 ) { $self->print_simple_body( $out, $is_smtp ) }
        elsif ( @parts == 1 ) { $parts[0]->print($out) }
        else { Carp::croak "can't handle message with >1 part\n"; }
    } else {
        $self->print_simple_body( $out, $is_smtp );
    }
    1;
}

sub print_simple_body {
    my ( $self, $out, $is_smtp ) = @_;
    my $attrs = $self->{Attrs};

    ### Coerce into a printable output handle:
    $out = MIME::Lite::IO_Handle->wrap($out);

    ### Get content-transfer-encoding:
    my $encoding = uc( $attrs->{'content-transfer-encoding'} );
    warn "M::L >>> Encoding using $encoding, is_smtp=" . ( $is_smtp || 0 ) . "\n"
      if $MIME::Lite::DEBUG;

    if ( defined( $self->{Data} ) ) {
      DATA:
        {
            local $_ = $encoding;

            /^BINARY$/ and do {
                $is_smtp and $self->{Data} =~ s/(?!\r)\n\z/\r/;
                $out->print( $self->{Data} );
                last DATA;
            };
            /^8BIT$/ and do {
                $out->print( encode_8bit( $self->{Data} ) );
                last DATA;
            };
            /^7BIT$/ and do {
                $out->print( encode_7bit( $self->{Data} ) );
                last DATA;
            };
            /^QUOTED-PRINTABLE$/ and do {
                ### UNTAINT since m//mg on tainted data loops forever:
                my ($untainted) = ( $self->{Data} =~ m/\A(.*)\Z/s );

                ### Encode it line by line:
                while ( $untainted =~ m{^(.*[\r\n]*)}smg ) {
                    $out->print( encode_qp($1) );    ### have to do it line by line...
                }
                last DATA;
            };
            /^BASE64/ and do {
                $out->print( encode_base64( $self->{Data} ) );
                last DATA;
            };
            Carp::croak "unsupported encoding: `$_'\n";
        }
    }

    elsif ( defined( $self->{Path} ) || defined( $self->{FH} ) ) {
        no strict 'refs';    ### in case FH is not an object
        my $DATA;

        ### Open file if necessary:
        if ( defined( $self->{Path} ) ) {
            $DATA = new FileHandle || Carp::croak "can't get new filehandle\n";
            $DATA->open("$self->{Path}")
              or Carp::croak "open $self->{Path}: $!\n";
        } else {
            $DATA = $self->{FH};
        }
        CORE::binmode($DATA) if $self->binmode;

        ### Encode piece by piece:
      PATH:
        {
            local $_ = $encoding;

            /^BINARY$/ and do {
                my $last = "";
                while ( read( $DATA, $_, 2048 ) ) {
                    $out->print($last) if length $last;
                    $last = $_;
                }
                if ( length $last ) {
                    $is_smtp and $last =~ s/(?!\r)\n\z/\r/;
                    $out->print($last);
                }
                last PATH;
            };
            /^8BIT$/ and do {
                $out->print( encode_8bit($_) ) while (<$DATA>);
                last PATH;
            };
            /^7BIT$/ and do {
                $out->print( encode_7bit($_) ) while (<$DATA>);
                last PATH;
            };
            /^QUOTED-PRINTABLE$/ and do {
                $out->print( encode_qp($_) ) while (<$DATA>);
                last PATH;
            };
            /^BASE64$/ and do {
                $out->print( encode_base64($_) ) while ( read( $DATA, $_, 45 ) );
                last PATH;
            };
            Carp::croak "unsupported encoding: `$_'\n";
        }

        ### Close file:
        close $DATA if defined( $self->{Path} );
    }

    else {
        Carp::croak "no data in this part\n";
    }
    1;
}


sub print_header {
    my ( $self, $out ) = @_;

    ### Coerce into a printable output handle:
    $out = MIME::Lite::IO_Handle->wrap($out);

    ### Output the header:
    $out->print( $self->header_as_string );
    1;
}

#------------------------------

=item as_string

I<Instance method.>
Return the entire message as a string, with a header and an encoded body.

=cut


sub as_string {
    my $self = shift;
    my $buf  = "";
    my $io   = ( wrap MIME::Lite::IO_Scalar \$buf);
    $self->print($io);
    return $buf;
}
*stringify = \&as_string;    ### backwards compatibility
*stringify = \&as_string;    ### ...twice to avoid warnings :)


sub body_as_string {
    my $self = shift;
    my $buf  = "";
    my $io   = ( wrap MIME::Lite::IO_Scalar \$buf);
    $self->print_body($io);
    return $buf;
}
*stringify_body = \&body_as_string;    ### backwards compatibility
*stringify_body = \&body_as_string;    ### ...twice to avoid warnings :)

sub fields_as_string {
    my ( $self, $fields ) = @_;
    my $out = "";
    foreach (@$fields) {
        my ( $tag, $value ) = @$_;
        next if ( $value eq '' );         ### skip empties
        $tag =~ s/\b([a-z])/uc($1)/ge;    ### make pretty
        $tag =~ s/^mime-/MIME-/i;         ### even prettier
        $out .= "$tag: $value\n";
    }
    return $out;
}

#------------------------------

=item header_as_string

I<Instance method.>
Return the header as a string.

=cut


sub header_as_string {
    my $self = shift;
    $self->fields_as_string( $self->fields );
}
*stringify_header = \&header_as_string;    ### backwards compatibility
*stringify_header = \&header_as_string;    ### ...twice to avoid warnings :)

=back

=cut


#==============================
#==============================

=head2 Sending

=over 4

=cut




sub send {
    my $self = shift;
    my $meth = shift;

    if ( ref($self) ) {    ### instance method:
        my ( $method, @args );
        if (@_) {          ### args; use them just this once
            $method = 'send_by_' . $meth;
            @args   = @_;
        } else {           ### no args; use defaults
            $method = "send_by_$Sender";
            @args   = @{ $SenderArgs{$Sender} || [] };
        }
        $self->verify_data if $AUTO_VERIFY;    ### prevents missing parts!
        Carp::croak "Unknown send method '$meth'" unless $self->can($method);
        return $self->$method(@args);
    } else {                                   ### class method:
        if (@_) {
            my @old = ( $Sender, @{ $SenderArgs{$Sender} } );
            $Sender              = $meth;
            $SenderArgs{$Sender} = [@_];       ### remaining args
            return @old;
        } else {
            Carp::croak "class method send must have HOW... arguments\n";
        }
    }
}




sub send_by_sendmail {
    my $self = shift;
    my $return;
    if ( @_ == 1 and !ref $_[0] ) {
        ### Use the given command...
        my $sendmailcmd = shift @_;

        ### Do it:
        local *SENDMAIL;
        open SENDMAIL, "|$sendmailcmd" or Carp::croak "open |$sendmailcmd: $!\n";
        $self->print( \*SENDMAIL );
        close SENDMAIL;
        $return = ( ( $? >> 8 ) ? undef: 1 );
    } else {    ### Build the command...
        my %p = map { UNIVERSAL::isa( $_, 'ARRAY' ) ? @$_
                    : UNIVERSAL::isa( $_, 'HASH' )  ? %$_
                    :                                  $_
                    } @_;

        $p{Sendmail} = $SENDMAIL unless defined $p{Sendmail};

        ### Start with the command and basic args:
        my @cmd = ( $p{Sendmail}, @{ $p{BaseArgs} || [ '-t', '-oi', '-oem' ] } );

        ### See if we are forcibly setting the sender:
        $p{SetSender} ||= defined( $p{FromSender} );

        ### Add the -f argument, unless we're explicitly told NOT to:
        if ( $p{SetSender} ) {
            my $from = $p{FromSender} || ( $self->get('From') )[0];
            if ($from) {
                my ($from_addr) = extract_full_addrs($from);
                push @cmd, "-f$from_addr" if $from_addr;
            }
        }

        ### Open the command in a taint-safe fashion:
        my $pid = open SENDMAIL, "|-";
        defined($pid) or die "open of pipe failed: $!\n";
        if ( !$pid ) {    ### child
            exec(@cmd) or die "can't exec $p{Sendmail}: $!\n";
            ### NOTREACHED
        } else {          ### parent
            $self->print( \*SENDMAIL );
            close SENDMAIL || die "error closing $p{Sendmail}: $! (exit $?)\n";
            $return = 1;
        }
    }
    return $self->{last_send_successful} = $return;
}

my @_mail_opts     = qw( Size Return Bits Transaction Envelope );
my @_recip_opts    = qw( SkipBad );
my @_net_smtp_opts = qw( Hello LocalAddr LocalPort Timeout
                         ExactAddresses Debug );

sub __opts {
    my $args=shift;
    return map { exists $args->{$_} ? ( $_ => $args->{$_} ) : () } @_;
}

sub send_by_smtp {
    require Net::SMTP;
    my ($self,$hostname,%args)  = @_;
    # We may need the "From:" and "To:" headers to pass to the
    # SMTP mailer also.
    $self->{last_send_successful}=0;

    my @hdr_to = extract_only_addrs( scalar $self->get('To') );
    if ($AUTO_CC) {
        foreach my $field (qw(Cc Bcc)) {
            my $value = $self->get($field);
            push @hdr_to, extract_only_addrs($value)
                if defined($value);
        }
    }
    Carp::croak "send_by_smtp: nobody to send to for host '$hostname'?!\n"
        unless @hdr_to;

    $args{To} ||= \@hdr_to;
    $args{From} ||= extract_only_addrs( scalar $self->get('Return-Path') );
    $args{From} ||= extract_only_addrs( scalar $self->get('From') ) ;


    my %opts = __opts(\%args, @_net_smtp_opts);
    my $smtp = MIME::Lite::SMTP->new( $hostname, %opts )
      or Carp::croak "SMTP Failed to connect to mail server: $!\n";

    # Possibly authenticate
    if ( defined $args{AuthUser} and defined $args{AuthPass}
         and !$args{NoAuth} )
    {
        if ($smtp->supports('AUTH',500,["Command unknown: 'AUTH'"])) {
            $smtp->auth( $args{AuthUser}, $args{AuthPass} )
                or die "SMTP auth() command failed: $!\n"
                   . $smtp->message . "\n";
        } else {
            die "SMTP auth() command not supported on $hostname\n";
        }
    }

    # Send the mail command
    %opts = __opts( \%args, @_mail_opts);
    $smtp->mail( $args{From}, %opts ? \%opts : () )
      or die "SMTP mail() command failed: $!\n"
             . $smtp->message . "\n";

    # Send the recipients command
    %opts = __opts( \%args, @_recip_opts);
    $smtp->recipient( @{ $args{To} }, %opts ? \%opts : () )
      or die "SMTP recipient() command failed: $!\n"
             . $smtp->message . "\n";

    # Send the data
    $smtp->data()
      or die "SMTP data() command failed: $!\n"
             . $smtp->message . "\n";
    $self->print_for_smtp($smtp);

    # Finish the mail
    $smtp->dataend()
      or Carp::croak "Net::CMD (Net::SMTP) DATAEND command failed.\n"
      . "Last server message was:"
      . $smtp->message
      . "This probably represents a problem with newline encoding ";

    # terminate the session
    $smtp->quit;

    return $self->{last_send_successful} = 1;
}

=item last_send_successful

This method will return TRUE if the last send() or send_by_XXX() method call was
successful. It will return defined but false if it was not successful, and undefined
if the object had not been used to send yet.

=cut


sub last_send_successful {
    my $self = shift;
    return $self->{last_send_successful};
}

sub send_by_smtp_simple {
    my ( $self, @args ) = @_;
    $self->{last_send_successful} = 0;
    ### We need the "From:" and "To:" headers to pass to the SMTP mailer:
    my $hdr = $self->fields();

    my $from_header = $self->get('From');
    my ($from) = extract_only_addrs($from_header);

    warn "M::L>>> $from_header => $from" if $MIME::Lite::DEBUG;


    my $to = $self->get('To');

    ### Sanity check:
    defined($to)
        or Carp::croak "send_by_smtp: missing 'To:' address\n";

    ### Get the destinations as a simple array of addresses:
    my @to_all = extract_only_addrs($to);
    if ($AUTO_CC) {
        foreach my $field (qw(Cc Bcc)) {
            my $value = $self->get($field);
            push @to_all, extract_only_addrs($value)
                if defined($value);
        }
    }

    ### Create SMTP client:
    require Net::SMTP;
    my $smtp = MIME::Lite::SMTP->new(@args)
      or Carp::croak("Failed to connect to mail server: $!\n");
    $smtp->mail($from)
      or Carp::croak( "SMTP MAIL command failed: $!\n" . $smtp->message . "\n" );
    $smtp->to(@to_all)
      or Carp::croak( "SMTP RCPT command failed: $!\n" . $smtp->message . "\n" );
    $smtp->data()
      or Carp::croak( "SMTP DATA command failed: $!\n" . $smtp->message . "\n" );

    ### MIME::Lite can print() to anything with a print() method:
    $self->print_for_smtp($smtp);

    $smtp->dataend()
      or Carp::croak(   "Net::CMD (Net::SMTP) DATAEND command failed.\n"
                      . "Last server message was:"
                      . $smtp->message
                      . "This probably represents a problem with newline encoding " );
    $smtp->quit;
    $self->{last_send_successful} = 1;
    1;
}

#------------------------------
#
# send_by_sub [\&SUBREF, [ARGS...]]
#
# I<Instance method, private.>
# Send the message via an anonymous subroutine.
#
sub send_by_sub {
    my ( $self, $subref, @args ) = @_;
    $self->{last_send_successful} = &$subref( $self, @args );

}

#------------------------------

=item sendmail COMMAND...

I<Class method, DEPRECATED.>
Declare the sender to be "sendmail", and set up the "sendmail" command.
I<You should use send() instead.>

=cut


sub sendmail {
    my $self = shift;
    $self->send( 'sendmail', join( ' ', @_ ) );
}

=back

=cut


#==============================
#==============================

=head2 Miscellaneous

=over 4

=cut


#------------------------------

=item quiet ONOFF

I<Class method.>
Suppress/unsuppress all warnings coming from this module.

    MIME::Lite->quiet(1);       ### I know what I'm doing

I recommend that you include that comment as well.  And while
you type it, say it out loud: if it doesn't feel right, then maybe
you should reconsider the whole line.  C<;-)>

=cut


sub quiet {
    my $class = shift;
    $QUIET = shift if @_;
    $QUIET;
}

=back

=cut



package MIME::Lite::SMTP;


use strict;
use vars qw( @ISA );
@ISA = qw(Net::SMTP);

# some of the below is borrowed from Data::Dumper
my %esc = ( "\a" => "\\a",
            "\b" => "\\b",
            "\t" => "\\t",
            "\n" => "\\n",
            "\f" => "\\f",
            "\r" => "\\r",
            "\e" => "\\e",
);

sub _hexify {
    local $_ = shift;
    my @split = m/(.{1,16})/gs;
    foreach my $split (@split) {
        ( my $txt = $split ) =~ s/([\a\b\t\n\f\r\e])/$esc{$1}/sg;
        $split =~ s/(.)/sprintf("%02X ",ord($1))/sge;
        print STDERR "M::L >>> $split : $txt\n";
    }
}

sub print {
    my $smtp = shift;
    $MIME::Lite::DEBUG and _hexify( join( "", @_ ) );
    $smtp->datasend(@_)
      or Carp::croak(   "Net::CMD (Net::SMTP) DATASEND command failed.\n"
                      . "Last server message was:"
                      . $smtp->message
                      . "This probably represents a problem with newline encoding " );
}


package MIME::Lite::IO_Handle;

sub wrap {
    my ( $class, $fh ) = @_;
    no strict 'refs';

    ### Get default, if necessary:
    $fh      or $fh = select;    ### no filehandle means selected one
    ref($fh) or $fh = \*$fh;     ### scalar becomes a globref

    ### Stop right away if already a printable object:
    return $fh if ( ref($fh) and ( ref($fh) ne 'GLOB' ) );

    ### Get and return a printable interface:
    bless \$fh, $class;          ### wrap it in a printable interface
}

### Print:
sub print {
    my $self = shift;
    print {$$self} @_;
}


package MIME::Lite::IO_Scalar;

sub wrap {
    my ( $class, $scalarref ) = @_;
    defined($scalarref) or $scalarref = \"";
    bless $scalarref, $class;
}

sub print {
    ${$_[0]} .= join( '', @_[1..$#_] );
    1;
}


package MIME::Lite::IO_ScalarArray;

sub wrap {
    my ( $class, $arrayref ) = @_;
    defined($arrayref) or $arrayref = [];
    bless $arrayref, $class;
}

### Print:
sub print {
    my $self = shift;
    push @$self, @_;
    1;
}

1;
__END__