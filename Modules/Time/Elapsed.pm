package Time::Elapsed;
 use strict;

 my $PACK = __PACKAGE__;
 use vars qw( $VERSION @ISA );
 $VERSION = '0.06';

sub new { bless {}, ref($_[0])||$_[0] }

   *cvt_secs_print = \&convert;

sub convert
{   my($class,$start,$end) = @_;

    return 0 unless $start;

    my $time = ( $end ? int($end - $start) : int($start) );
    return 0 unless $time > 0;

    my $str = "";
    ($time,$str) = $class->_cvt($time, 60,"second",$str);
    ($time,$str) = $class->_cvt($time, 60,"minute",$str);
    ($time,$str) = $class->_cvt($time, 24,"hour",  $str);
    ($time,$str) = $class->_cvt($time,365,"day",   $str);
    ($time,$str) = $class->_cvt($time,  0,"year",  $str);

    return $str;
}

sub granular
{   my($class,$start,$end) = @_;

    my($yrs,$days,$hrs,$mins,$secs) = $class->convertArgs($start,$end);

    $yrs   and return sprintf("%0.2f yrs",  $yrs  + ($days / 365) );
    $days  and return sprintf("%0.2f days", $days + ($hrs  /  24) );
    $hrs   and return sprintf("%0.2f hrs",  $hrs  + ($mins /  60) );
    $mins  and return sprintf("%0.2f mins", $mins + ($secs /  60) );
    $secs  and return sprintf(   "%d secs", $secs);
    return "0 secs";
}

sub days
{   my($class,$start,$end) = @_;

    my($yrs,$days,$hrs,$mins,$secs) = $class->convertArgs($start,$end);

    $days += ($yrs * 365);
    $days += ($hrs /  24);
    $days  = sprintf("%0.2f", $days);
    $days  = $class->addCommasToNumber( $days );
    $days .= " day";
    $days .= "s" unless $days eq "1.00 day";

    return $days;
}

sub hours
{   my($class,$start,$end) = @_;

    my($yrs,$days,$hrs,$mins,$secs) = $class->convertArgs($start,$end);

    $hrs += ($yrs * 365 * 24);
    $hrs += ($days * 24);
    $hrs += ($mins / 60);
    $hrs  = sprintf("%0.2f", $hrs);
    $hrs  = $class->addCommasToNumber( $hrs );
    $hrs .= " hour";
    $hrs .= "s" unless $hrs eq "1.00 hour";

    return $hrs;
}

sub addCommasToNumber
{   my($class,$string,$forceDecimal) = @_;

    $string = reverse $string;
    $string =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    $string =~ s/^(\d)\./0$1./;       # remember, it's still reversed here ;-)
    $forceDecimal and $string = "00.".$string if $string !~ /\./;

    return scalar reverse $string;
}


sub convertArgs
{   my($class,$start,$end) = @_;

    return(0,0,0,0,0) unless $start;

    my $time = ( $end ? int($end - $start) : int($start) );
    return(0,0,0,0,0) unless $time > 0;

    my($secs,$mins,$hrs,$days,$yrs) = (0,0,0,0,0);

    ($time,$secs) = $class->_cvt($time, 60,"second","ArgOnly");
    ($time,$mins) = $class->_cvt($time, 60,"minute","ArgOnly");
    ($time,$hrs)  = $class->_cvt($time, 24,"hour",  "ArgOnly");
    ($time,$days) = $class->_cvt($time,365,"day",   "ArgOnly");
    $yrs          = $time;

    return($yrs,$days,$hrs,$mins,$secs);
}

sub _cvt
{   my($class,$time,$num,$type,$str) = @_;

    my $incr = 0;
    if ($num) {
    	$incr = $time % $num;
    	$time = int($time / $num);
    	$time = 0 if $time < 0;
    } else {
    	$incr = $time;
    }
    return($time,$incr) if $str eq "ArgOnly";
    return($time,$str) if ($incr == 0);

    my $tmp = sprintf "%d %s%s", $incr, $type, ($incr == 1) ? "" : "s";

    $str = ($str ? "$tmp, $str" : $tmp);
    return($time,$str);
}

1;
