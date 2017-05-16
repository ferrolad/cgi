package Plugins::Captcha::image;

sub generate {
   my ($self, $number, $fname) = @_;
   return if $ses->{captcha_mode} !~ /^(1|image)$/i;

   eval {require GD;};
   die"Can't init GD perl module" if $@;

   require GD::SecurityImage;
   GD::SecurityImage->import;

   my $image = GD::SecurityImage->new(width => 80,
         height  => 26,
         lines   => 4,
         rndmax  => 4,
         gd_font => 'giant',
         thickness => 1.2,
         );
   $image->random($number);
   $image->create('normal', 'circle', [0,0,0], [100,100,100]);
   $image->particle(150);
   my ($image_data, undef, $number) = $image->out(force => 'jpeg',compress =>15);

   open(FILE,">$c->{site_path}/captchas/$fname.jpg");
   print FILE $image_data;
   close FILE;
   my $image_url = "$c->{site_url}/captchas/$fname.jpg";

   return <<BLOCK
<table><tr><td colspan=2><b>$ses->{lang}->{lang_enter_code}:</b></td></tr>
<tr>
	<td align=right><img src="$image_url"/></td>
	<td align=left valign=middle><input type="text" name="code" class="captcha_code"></td>
</tr>
</table>
BLOCK
;
}

sub check {
   my ($self, $f, $answer) = @_;
   return if $ses->{captcha_mode} !~ /^(1|image)$/i;

   my $hash = $f->{rand};
   $hash =~ s/[^0-9a-z]//g;
   unless(-e "$c->{site_path}/captchas/$hash.jpg"){$self->{form}->{msg}="Expired session";return 0;}
   unlink("$c->{site_path}/captchas/$hash.jpg");

   return $f->{code} eq $answer;
}

1;
