package Plugins::Captcha::text;
use List::Util qw(shuffle);

sub generate
{
   my ($self, $number) = @_;
   return if $c->{captcha_mode} !~ /^(2|text)$/i;

   my @arr = split '', $number;
   my $i=0;
   @arr = map { {x=>(int(rand(5))+6+18*$i++), y =>3+int(rand(5)), char=>'&#'.(48+$_).';'} } @arr;
   @arr = shuffle(@arr);

   my $itext;
   $itext = "<div style='width:80px;height:26px;font:bold 13px Arial;background:#ccc;text-align:left;direction:ltr;'>";
   $itext.="<span style='position:absolute;padding-left:$_->{x}px;padding-top:$_->{y}px;'>$_->{char}</span>" for @arr;
   $itext.="</div>";

   return <<BLOCK
<table><tr><td colspan=2><b>$ses->{lang}->{lang_enter_code}:</b></td></tr>
<tr>
	<td align=right>$itext</td>
	<td align=left valign=middle><input type="text" name="code" class="captcha_code"></td>
</tr>
</table>
BLOCK
}

sub check
{
   my ($self, $f, $answer) = @_;
   return if $c->{captcha_mode} !~ /^(2|text)$/i;
   return $f->{code} eq $answer;
}

1;
