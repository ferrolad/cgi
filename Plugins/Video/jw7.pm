package Plugins::Video::jw7;
use base Plugins::Video::jw5;
use strict;
use vars qw($ses);
use XFileConfig;

sub options {
	return {
		name=>'jw7', title=>'JWPlayer 7',
		listed=>1,
		html5=>1,
		s_fields=>[
			{title=>'Player License', name=>'jw7_license', type=>'text'},
			{title=>'Player Skin', name=>'jw7_skin', type=>'text'},
			]
		};
}

1;
