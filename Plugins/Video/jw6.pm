package Plugins::Video::jw6;
use base Plugins::Video::jw5;
use strict;
use vars qw($ses);
use XFileConfig;

sub options {
	return {
		name=>'jw6', title=>'JWPlayer 6',
		listed=>1,
		html5=>1,
		s_fields=>[
			{title=>'Player License', name=>'jw6_license', type=>'text'},
			{title=>'Player Skin', name=>'jw6_skin', type=>'text'},
			]
		};
}

1;
