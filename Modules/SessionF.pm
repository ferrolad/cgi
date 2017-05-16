package SessionF;
use strict;

our @plugins;
sub new {
	my $class = shift;
	$class = ref( $class ) || $class;
	my $self = shift||{} ;
	bless $self, $class;
	return $self;
}

sub LoadPlugins {                        
	my $self = shift;
	my $plugdir = 'Plugins/Leech';
	opendir(DIR, $plugdir) || die "can't opendir $plugdir: $!";
	my @files = grep { /.pm$/ && -f "$plugdir/$_" } readdir(DIR);
	closedir DIR;
	@plugins = ();

	my @e_sites = ( $self->{pg} =~ m/../g );;
	my @d_sites = ();
	foreach my $file(@files) {
		eval {require "$plugdir/$file"};
		unless($@) {
			$file =~ s/\.pm$//;
			$file = 'Plugins::'.$file;
			my $options = eval "\$${file}::options";
			$options->{ses} = $self;
			eval {$file = $file->new($options)};
			my $domain = $file->domain();
			my $plugin_prefix = $options->{plugin_prefix};
			push @d_sites, $plugin_prefix;
			push @plugins, $file;
		} else {
			print "Couldn't load $file: $@\n";
		}
	}
	$self->{plugins} = \@plugins;
}

sub getPlugins {
	my $self = shift;
	return $self->{plugins};
}

1;
