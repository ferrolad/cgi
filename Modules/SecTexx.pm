package SecTexx;

my $key='hui812p';

sub ImportCode
{
   my ($type)=@_;
   my ($ref)=[];
   
   filter_add(bless $ref);
}

sub FilterCode
{
   my ($self)=@_;
   my ($status);
   tr/A-Za-z0-9\+\-/a-zA-Z0-9\-\+/ if ($status=filter_read());
   $status=~s/x$key(.+?)y/sprintf("%xD",$1)/ge;
   return $status;
}
sub decode {my ($type)=@_;my ($key)=[];filter_add(bless $key);}sub output_decoded {my ($self)=@_;my ($code);tr/a-x/A-X/ if ($code=filter_read())>0;$code;}use Filter::Util::Call;
sub import {my ($type)=@_;my ($ref)=[];filter_add(bless $ref);}sub filter {my ($self)=@_;my ($st);tr/n-za-mN-ZA-M\+\- \&/a-zA-Z\-\+\& / if ($st=filter_read())>0;$st;}
1;