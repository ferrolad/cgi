package Plugins::Video::divx;
use strict;
use vars qw($ses);
use XFileConfig;
use HTTP::BrowserDetect;


sub options {
	return {
		listed => 0,
		};
}

sub makeCode {
	my ($self, $file, $direct_link) = @_;
	return if $file->{file_name} !~ /\.(avi|divx|mkv)$/i || $file->{file_size_encoded};

	my $browser = new HTTP::BrowserDetect( $ENV{HTTP_USER_AGENT} );
	my $mobile_device = 1 if $c->{mobile_design} && $browser->mobile;
	return if $mobile_device;

	my $code = qq[document.write('<object id="ie_vid" classid="clsid:67DABFBF-D0AB-41fa-9C46-CC0F21721616" width="$file->{vid_width}" height="$file->{vid_height}" codebase="http://go.divx.com/plugin/DivXBrowserPlugin.cab">
<param name="custommode" value="Stage6" />
<param name="wmode" value="transparent" />
<param name="previewImage" value="$file->{video_img_url}" />
<param name="allowContextMenu" value="false">
<param name="bannerEnabled" value="false" />
<param name="previewMessage" value="Play" />
<param name="autoPlay" value="false" />
<param name="src" value="$direct_link" />
<embed id="np_vid" type="video/divx" src="$direct_link" custommode="Stage6" wmode="transparent" width="$file->{vid_width}" height="$file->{vid_height}" previewImage="$file->{video_img_url}" autoPlay="false" bannerEnabled="false" previewImage="$file->{direct_img}" allowContextMenu="false" previewMessage="Play" pluginspage="http://go.divx.com/plugin/download/"></embed>
</object>');];
	$file->{divx}=1;
	return $ses->encodeJS($code);
}

1;
