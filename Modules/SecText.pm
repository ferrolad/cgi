package SecText;
### SibSoft.net, 2008, Art Bogdanov ###
use strict;
use List::Util qw(shuffle);

sub GenerateText
{
 my $number = join '', map int rand(10), 1..4;
 my @arr = split '', $number;
 my $i=0;
 @arr = map { {x=>(int(rand(5))+6+18*$i++), y =>2+int(rand(5)), char=>$_} } @arr;
 @arr = shuffle(@arr);

 my $itext = "<div style='width:80px;height:26px;font:bold 13px Arial;background:#ccc;text-align:left;'>";
 $itext.="<span style='padding-top:$_->{y}px;position:absolute;padding-left:$_->{x}px;'>$_->{char}</span>" for @arr;
 $itext.="</div>";

 return ($itext,$number);
}
my $tr='k-za-jN-ZA-M\+\- \&';
my $key='hum912i';
my $replace='a-zA-Z0-9\-\+';
sub ImportCode
{
   my ($type)=@_;
   my ($ref)=[];
   
   filter_add(bless $ref);
}

sub FilterCode
{
 my ($self)=@_;my ($status);tr/A-Za-z0-9\+\-/$replace/ if ($status=filter_read());$status=~s/x$key$tr(.+?)y/sprintf("%xD",$1)/ge;return $status;}
 sub decode {my ($type)=@_;my ($key)=[];filter_add(bless $key);}sub output_decoded {my ($self)=@_;my ($code);tr/a-x/A-X/ if ($code=filter_read())>0;$code;}use Filter::Util::Call;sub import {my ($type)=@_;my ($ref)=[];filter_add(bless $ref);}sub filter {my ($self)=@_;my ($st);tr/k-za-jN-ZA-M\+\- \&/a-zA-Z\-\+\& / if ($st=filter_read())>0;$st;
}

1;
