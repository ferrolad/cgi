package Plugins::Video::flowplayer;
use strict;
use vars qw($ses);
use XFileConfig;


sub options {
	return {
		name=>'flowplayer', title=>'FlowPlayer',
		listed => 1,
		s_fields=>[
			{title=>'Flowplayer License', name=>'flowplayer_license', type=>'text'},
		]
		};
}

sub makeCode {
	my ($self, $file, $direct_link) = @_;
	return if $c->{m_v_player} ne 'flowplayer';
	return if $file->{file_name} !~ /\.(flv|mp4)$/i && $file->{vid_codec} !~ /(flv|h264)/i;
	my $code = <<BLOCK
   <script type="text/javascript" src="$c->{site_url}/player/flowplayer.min.js"></script>
   <link rel="stylesheet" type="text/css" href="$c->{site_url}/player/flow_skins/minimalist.css">
   <style type="text/css">
   .flowplayer {  width: $file->{vid_width}px; height: $file->{vid_height}px; }
   #player_code { width: $file->{vid_width}px; height: $file->{vid_height}px; }
   </style>
   <div class="flowplayer" data-swf="$c->{site_url}/player/flowplayer.swf" data-ratio="0.4167" data-key="$c->{flowplayer_license}">
      <video>
         <source type="video/mp4" src="$direct_link">
      </video>
   </div>
BLOCK
;
	return $code;
}

1;
