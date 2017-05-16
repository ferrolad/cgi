package SecImage;
### SibSoft.net 2010 Art Bogdanov ###
use strict;
use List::Util qw(shuffle);
use XFileConfig;

sub GenerateImage
{
 my ($number,$fname) = @_;

 eval {require GD;};
 die"Can't init GD perl module" if $@;
 
 require GD::SecurityImage;
 GD::SecurityImage->import;

 my $image = GD::SecurityImage->new(width   => 80,
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
 return $image_url;
}

sub GenerateText
{
 my ($number) = @_;
 my @arr = split '', $number;
 my $i=0;
 @arr = map { {x=>(int(rand(5))+6+18*$i++), y =>3+int(rand(5)), char=>'&#'.(48+$_).';'} } @arr;
 @arr = shuffle(@arr);

 my $itext = "<div style='width:80px;height:26px;font:bold 13px Arial;background:#ccc;text-align:left;direction:ltr;'>";
 $itext.="<span style='position:absolute;padding-left:$_->{x}px;padding-top:$_->{y}px;'>$_->{char}</span>" for @arr;
 $itext.="</div>";

 return $itext;
}

1;
