package Plugins::Video::jw7;
use base Plugins::Video::jw6;
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
sub makeCode
{
	my ($self, $file, $direct_link) = @_;
	my $name = $self->options()->{name};
	return if $c->{m_v_player} ne $name;
	return if $file->{file_name} !~ /\.(flv|mp4)$/i && $file->{vid_codec} !~ /(flv|h264)/i;

	my $skin = sprintf("%s", $c->{"$name\_skin"}) if $c->{"$name\_skin"};
	my $code=<<ENP
  jwplayer("flvplayer").setup({
	 file: "$direct_link",
	 flashplayer: "$c->{site_url}/player/$name.swf",
	 image: "$file->{video_img_url}",
	 duration:"$file->{vid_length}",
	 width: $file->{vid_width},
	 height: $file->{vid_height},
	 provider: "http",
	 skin: {
	   name: "$skin",
	     },
	 modes: [ { type: "flash", src: "$c->{site_url}/player/$name.swf" },{ type: "html5", config:{file:'$direct_link','provider':'http'} }, { type: "download" } ],
  });
ENP
;
	my @code;
	push @code, "<span id='flvplayer'></span><script type='text/javascript' src='$c->{site_url}/player/$name.js'></script>";
	push @code, "<script type='text/javascript' src='$c->{site_url}/player/provider.html5.js'></script>" if $self->options()->{html5};
	push @code, '<script type="text/javascript">jwplayer.key="', $c->{"$name\_license"}, '";</script>' if $c->{"$name\_license"};
	push @code, $ses->encodeJS($code);
#	push @code, "<script>".$code."</script>";
	return join('', @code);
}

1;
