package Color::Palette;
use Moose;
# ABSTRACT: a set of named colors

use MooseX::Types::Moose qw(Str HashRef ArrayRef);
use Color::Palette::Types qw(RecursiveColorDict ColorDict Color);

=head1 DESCRIPTION

The libraries in the Color-Palette distribution are meant to make it easy to
build sets of named colors, and to write applications that can define and
validate the color names they required.

For example, a color palette might contain the following data:

  highlights => #f0f000
  background => #333
  sidebarBackground => #88d
  sidebarText       => 'highlights'
  sidebarBoder      => 'sidebarText'

Colors can be defined by a color specifier (a L<Graphics::Color> object,
a CSS-style hex triple, or an arrayref of RGB values) or by a name of another
color that appears in the palette.  If colors are defined in terms of another
color that doesn't exist, an exception will be raised.

Applications that wish to use color palettes can provide schemas that define
the names they expect to be present in a palette.  These schemas are
L<Color::Palette::Schema> objects.

A palette can be checked against a schema with the schema's C<check> method, or
may be reduced to the minimal set of colors needed to satisfy the schema with
the palette's C<optimized_for> method.

=attr colors

This attribute is a hashref.  Keys are color names and values are either Color
objects or names of other colors.  To get at the color object for a name
consult the C<L</color>> method.

=cut

has colors => (
  is   => 'bare',
  isa  => RecursiveColorDict,
  coerce   => 1,
  required => 1,
  reader   => '_colors',
);

=begin :private

=attr _resolved_colors

This attribute is just like C<colors>, but all values are Color objects.

=end :private

=cut

has _resolved_colors => (
  is   => 'ro',
  isa  => ColorDict,
  lazy => 1,
  traits   => [ 'Hash' ],
  coerce   => 1,
  required => 1,
  builder  => '_build_resolved_colors',
  handles  => {
    has_color   => 'exists',
    _get_color  => 'get',
    color_names => 'keys',
  },
);

sub _build_resolved_colors {
  my ($self) = @_;

  my $input = $self->_colors;

  my %output;

  for my $key (keys %$input) {
    my $value = $input->{ $key };
    next unless ref $value;

    $output{ $key } = $value;
  }

  for my $key (keys %$input) {
    my $value = $input->{ $key };
    next if ref $value;

    my %seen;
    my $curr = $key;
    REDIR: while (1) {
      Carp::confess "$key refers to missing color $curr"
        unless exists $input->{$curr};

      if ($output{ $curr }) {
        $output{ $key } = $output{ $curr };
        last REDIR;
      }

      $curr = $input->{ $curr };
      Carp::confess "looping at $curr" if $seen{ $curr }++;
    }
  }

  return \%output;
}

=method color

  my $color_obj = $palette->color('extremeHighlight');

This method will return the Color object to be used for the given name.

=cut

sub color {
  my ($self, $name) = @_;
  confess("no color named $name") unless my $color = $self->_get_color($name);

  return $color;
}

=method color_names

  my @names = $palette->color_names;

This method returns a list of all color names the object knows about.

=method as_css_hash

  my $triple_for = $palette->as_css_hash

This method returns a hashref.  Every color name known to the palette has an
entry, and the value is the CSS-safe hex string for the resolved color.  For
example, the output for the color scheme in the L</DESCRIPTION> section would
be:

  {
    highlights => '#f0f000',
    background => '#333333',
    sidebarBackground => #8888dd',
    sidebarText       => #f0f000',
    sidebarBoder      => #f0f000',
  }

=cut

sub as_css_hash {
  my ($self) = @_;
  my $output = {};
  $output->{$_} = $self->color($_)->as_css_hex for $self->color_names;
  return $output;
}

=method as_strict_css_hash

  my $hashref = $palette->as_strict_css_hash;

This method behaves just like C<L</as_css_hash>>, but the returned hashref is
tied so that trying to read values for keys that do not exist is fatal.  The
hash may also become read-only in the future.

=cut

sub as_strict_css_hash {
  my ($self) = @_;
  my $hashref = $self->as_css_hash;
  tie my %hash, 'Color::Palette::TiedStrictHash';
  %hash = %$hashref;
  return \%hash;
}

=method optimized_for

  my $optimized_palette = $palette->optimized_for($schema);

This method returns a new palette containing only the colors needed to fulfill
the requirements of the given schema.  This is useful for reducing a large
palette to the small set that must be embedded in a document.

C<optimize_for> redispatches to this method for historical reasons.

=cut

sub optimize_for {
  my $self = shift;
  # warn deprecated
  $self->optimized_for(@_);
}

sub optimized_for {
  my ($self, $checker) = @_;

  my $required_colors = $checker->required_colors;

  my %new_palette;
  for my $name (@{ $checker->required_colors }) {
    $new_palette{ $name } = $self->color($name);
  }

  (ref $self)->new({
    colors => \%new_palette,
  });
}

{
  package
    Color::Palette::TiedStrictHash;
  use Tie::Hash;
  BEGIN { our @ISA = qw(Tie::StdHash) }
  sub FETCH {
    my ($self, $key) = @_;
    die "no entry in palette hash for key $key"
      unless $self->EXISTS($key);
    return $self->SUPER::FETCH($key);
  }
}

1;
