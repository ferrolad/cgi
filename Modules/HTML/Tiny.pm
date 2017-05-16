package HTML::Tiny;

use strict;
use Carp;

use vars qw/$VERSION/;
$VERSION = '1.05';

BEGIN {

  # http://www.w3schools.com/tags/default.asp
  for my $tag (
    qw( a abbr acronym address area b base bdo big blockquote body br
    button caption cite code col colgroup dd del div dfn dl dt em
    fieldset form frame frameset h1 h2 h3 h4 h5 h6 head hr html i
    iframe img input ins kbd label legend li link map meta noframes
    noscript object ol optgroup option p param pre q samp script select
    small span strong style sub sup table tbody td textarea tfoot th
    thead title tr tt ul var )
   ) {
    no strict 'refs';
    *$tag = sub { shift->auto_tag( $tag, @_ ) };
  }
}

# Tags that are closed (<br /> versus <br></br>)
my @DEFAULT_CLOSED
 = qw( area base br col frame hr img input link meta param );

# Tags that get a trailing newline
my @DEFAULT_NEWLINE = qw( html head body div p tr table );

my %DEFAULT_AUTO = (
  suffix => '',
  method => 'tag'
);


sub new {
  my $self = bless {}, shift;

  my %params = @_;
  my $mode = $params{'mode'} || 'xml';

  croak "Unknown mode: $mode"
   unless $mode eq 'xml'
     or $mode eq 'html';

  $self->{'_mode'} = $mode;

  $self->_set_auto( 'method', 'closed', @DEFAULT_CLOSED );
  $self->_set_auto( 'suffix', "\n",     @DEFAULT_NEWLINE );
  return $self;
}

sub _set_auto {
  my ( $self, $kind, $value ) = splice @_, 0, 3;
  $self->{autotag}->{$kind}->{$_} = $value for @_;
}

sub tag {
  my ( $self, $name ) = splice @_, 0, 2;

  my %attr = ();
  my @out  = ();

  for my $a ( @_ ) {
    if ( 'HASH' eq ref $a ) {

      # Merge into attributes
      %attr = ( %attr, %$a );
    }
    else {

      # Generate markup
      push @out,
         $self->_tag( 0, $name, \%attr )
       . $self->stringify( $a )
       . $self->close( $name );
    }
  }

  # Special case: generate an empty tag pair if there's no content
  push @out, $self->_tag( 0, $name, \%attr ) . $self->close( $name )
   unless @out;

  return wantarray ? @out : join '', @out;
}


sub open { shift->_tag( 0, @_ ) }

sub close { "</$_[1]>" }


sub closed { shift->_tag( 1, @_ ) }


sub auto_tag {
  my ( $self, $name ) = splice @_, 0, 2;
  my ( $method, $post )
   = map { $self->{autotag}->{$_}->{$name} || $DEFAULT_AUTO{$_} }
   ( 'method', 'suffix' );
  my @out = map { $_ . $post } $self->$method( $name, @_ );
  return wantarray ? @out : join '', @out;
}



sub stringify {
  my ( $self, $obj ) = @_;
  if ( ref $obj ) {

    # Flatten array refs...
    if ( 'ARRAY' eq ref $obj ) {
      # Check for deferred method call specified as a scalar
      # ref...
      if ( @$obj && 'SCALAR' eq ref $obj->[0] ) {
        my ( $method, @args ) = @$obj;
        return join '', $self->$$method( @args );
      }
      return join '', map { $self->stringify( $_ ) } @$obj;
    }

    # ...stringify objects...
    my $str;
    return $str if eval { $str = $obj->as_string; 1 };
  }

  # ...default stringification
  return "$obj";
}



sub url_encode {
  my $str = $_[0]->stringify( $_[1] );
  $str
   =~ s/([^A-Za-z0-9_~])/$1 eq ' ' ? '+' : sprintf("%%%02x", ord($1))/eg;
  return $str;
}

=item C<< url_decode( $str ) >>

URL decode a string. Reverses the effect of C<< url_encode >>.

  $h->url_decode( '+%3chello%3e+' )   # returns ' <hello> '

=cut

sub url_decode {
  my $str = $_[1];
  $str =~ s/[+]/ /g;
  $str =~ s/%([0-9a-f]{2})/chr(hex($1))/ieg;
  return $str;
}

sub query_encode {
  my $self = shift;
  my $hash = shift || {};
  return join '&', map {
    join( '=', map { $self->url_encode( $_ ) } ( $_, $hash->{$_} ) )
  } sort grep { defined $hash->{$_} } keys %$hash;
}

=item C<< entity_encode( $str ) >>

Encode the characters '<', '>', '&', '\'' and '"' as their HTML entity
equivalents:

  print $h->entity_encode( '<>\'"&' );

would print:

  &lt;&gt;&apos;&quot;&amp;

=cut

{
  my %ENT_MAP = (
    '&'   => '&amp;',
    '<'   => '&lt;',
    '>'   => '&gt;',
    '"'   => '&#34;',    # shorter than &quot;
    "'"   => '&#39;',    # HTML does not define &apos;
    "\xA" => '&#10;',
    "\xD" => '&#13;',
  );

  my $text_special = qr/([<>&'"])/;
  my $attr_special = qr/([<>&'"\x0A\x0D])/;    # FIXME needs tests

  sub entity_encode {
    my $str = $_[0]->stringify( $_[1] );
    my $char_rx = $_[2] ? $attr_special : $text_special;
    $str =~ s/$char_rx/$ENT_MAP{$1}/eg;
    return $str;
  }
}

sub _attr {
  my ( $self, $attr, $val ) = @_;

  if ( ref $val ) {
    return $attr if not $self->_xml_mode;
    $val = $attr;
  }

  my $enc_val = $self->entity_encode( $val, 1 );
  return qq{$attr="$enc_val"};
}

sub _xml_mode { $_[0]->{'_mode'} eq 'xml' }

sub validate_tag {
  # Do nothing. Subclass to throw an error for invalid tags
}

sub _tag {
  my ( $self, $closed, $name ) = splice @_, 0, 3;

  croak "Attributes must be passed as hash references"
   if grep { 'HASH' ne ref $_ } @_;

  # Merge attribute hashes
  my %attr = map { %$_ } @_;

  $self->validate_tag( $closed, $name, \%attr );

  # Generate markup
  my $tag = join( ' ',
    "<$name",
    map { $self->_attr( $_, $attr{$_} ) }
     sort grep { defined $attr{$_} } keys %attr );

  return $tag . ( $closed && $self->_xml_mode ? ' />' : '>' );
}

{
  my @UNPRINTABLE = qw(
   z    x01  x02  x03  x04  x05  x06  a
   x08  t    n    v    f    r    x0e  x0f
   x10  x11  x12  x13  x14  x15  x16  x17
   x18  x19  x1a  e    x1c  x1d  x1e  x1f
  );

  sub _json_encode_ref {
    my ( $self, $seen, $obj ) = @_;
    my $type = ref $obj;
    if ( 'HASH' eq $type ) {
      return '{' . join(
        ',',
        map {
             $self->_json_encode( $seen, $_ ) . ':'
           . $self->_json_encode( $seen, $obj->{$_} )
         } sort keys %$obj
      ) . '}';
    }
    elsif ( 'ARRAY' eq $type ) {
      return
         '['
       . join( ',', map { $self->_json_encode( $seen, $_ ) } @$obj )
       . ']';
    }
    elsif ( UNIVERSAL::can( $obj, 'can' ) && $obj->can( 'TO_JSON' ) ) {
      return $self->_json_encode( $seen, $obj->TO_JSON );
    }
    else {
      croak "Can't json_encode a $type";
    }
  }

  # Minimal JSON encoder. Provided here for completeness - it's useful
  # when generating JS.
  sub _json_encode {
    my ( $self, $seen, $obj ) = @_;

    return 'null' unless defined $obj;

    if ( my $type = ref $obj ) {
      croak "json_encode can't handle self referential structures"
       if $seen->{$obj}++;
      my $rep = $self->_json_encode_ref( $seen, $obj );
      delete $seen->{$obj};
      return $rep;
    }

    return $obj if $obj =~ /^-?\d+(?:[.]\d+)?$/;

    $obj = $self->stringify( $obj );
    $obj =~ s/\\/\\\\/g;
    $obj =~ s/"/\\"/g;
    $obj =~ s/ ( [\x00-\x1f] ) / '\\' . $UNPRINTABLE[ ord($1) ] /gex;

    return qq{"$obj"};
  }
}



sub json_encode { shift->_json_encode( {}, @_ ) }

1;
