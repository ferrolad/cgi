package Plugins::Payments::paypal;
use Payments;
use base 'Payments';
use LWP::UserAgent;
use vars qw($ses $c);
use strict;


sub options {
	return {
		name=>'paypal', title=>'PayPal', account_field=>'paypal_email', image=>'buy_paypal.gif', 
		listed_reseller=>'1',
		s_fields=>[
			{title=>'Your PayPal E-mail', name=>'paypal_email', type=>'text'},
			{title=>'PayPal subscriptions', name=>'paypal_subscription', type=>'checkbox', id=>'ppsub', comment=>'Enabled'},
			{title=>'PayPal trial period', name=>'paypal_trial_days', type=>'text', id=>'pptrial', size=>2, comment=>'days'},
			]
		};
}

sub checkout {
	my ($self, $f) = @_;
	return if $f->{type} ne 'paypal';
	my $plans = $ses->ParsePlans($c->{payment_plans}, 'hash');
    if($c->{paypal_subscription} && !$f->{reseller})
    {
       my $days = $f->{days}||$plans->{$f->{amount}};
       my $time_code='D' if $days<=90;
       unless($time_code){$time_code='M';$days=sprintf("%.0f",$days/30);}
       my $trial;
       if($c->{paypal_trial_days})
       {
          $trial=qq[<input type="hidden" name="a1" value="0">\n<input type="hidden" name="p1" value="$c->{paypal_trial_days}">\n<input type="hidden" name="t1" value="D">];
       }
       print"Content-type:text/html\n\n";
print<<END
<HTML><BODY onLoad="document.F1.submit();">
<form name="F1" action="$c->{paypal_url}" method="post">
<input type="hidden" name="cmd" value="_xclick-subscriptions">
<input type="hidden" name="business" value="$c->{paypal_email}">
<input type="hidden" name="currency_code" value="$c->{currency_code}">
<input type="hidden" name="no_shipping" value="1">
<input type="hidden" name="item_name" value="$c->{item_name}">
$trial
<input type="hidden" name="a3" value="$f->{amount}">
<input type="hidden" name="p3" value="$days">
<input type="hidden" name="t3" value="$time_code">
<input type="hidden" name="src" value="1">
<input type="hidden" name="sra" value="1">
<input type="hidden" name="rm" value="2">
<input type="hidden" name="no_note" value="1">
<input type="hidden" name="custom" value="$f->{id}">
<input type="hidden" name="return" value="$c->{site_url}/?payment_complete=$f->{id}-1">
<input type="hidden" name="notify_url" value="$c->{site_cgi}/ipn.cgi">
<input type="submit" value="Redirecting...">
</form>
</BODY></HTML>
END
;
       exit;
    }
    else
	{
		print"Content-type:text/html\n\n";
		print <<END
		<HTML><BODY onLoad="document.F1.submit();">
		<form name="F1" action="$c->{paypal_url}" method="post">
		<input type="hidden" name="cmd" value="_xclick">
		<input type="hidden" name="no_shipping" value="1">
		<input type="hidden" name="no_note" value="1">
		<input type="hidden" name="cbt" value="Start using $c->{site_name}!">
		<input type="hidden" name="currency_code" value="$c->{currency_code}">
		<input type="hidden" name="item_name" value="$c->{item_name}">
		<input type="hidden" name="return" value="$c->{site_url}/?payment_complete=$f->{id}-0">
		<input type="hidden" name="cancel_return" value="$c->{site_url}">
		<input type="hidden" name="notify_url" value="$c->{site_cgi}/ipn.cgi">
		<input type="hidden" name="custom" value="$f->{id}">
		<input type="hidden" name="amount" value="$f->{amount}">
		<input type="hidden" name="business" value="$c->{paypal_email}">
		<input type="submit" value="Redirecting...">
		</form>
		</BODY></HTML>
END
;
	}
	exit;
}

sub error {
	print STDERR "$_[0]\n";
	print "Content-type: text/plain\n\n";
	exit;
}

sub verify {
	my ($self, $f) = @_;
	return if !$f->{custom};
	my $transaction = $ses->db->SelectRow("SELECT * FROM Transactions WHERE id=?",$f->{custom}) || error( "Transaction not found: '$f->{custom}'"  );

	$ses->db->Exec("UPDATE Transactions SET txn_id=? WHERE id=?",$f->{txn_id}||'',$transaction->{id});
	error("Subscription OK") if $f->{txn_type} eq 'subscr_signup' && $transaction->{verified};
	error("Subscription cancelled") if $f->{txn_type} eq 'subscr_cancel';
	error("Subscription expired") if $f->{txn_type} eq 'subscr_eot';
	error("Subscription failed") if $f->{txn_type} eq 'subscr_failed';
	error("Payment suspended") if $f->{txn_type} eq 'recurring_payment_suspended_due_to_max_failed_payment';

	error("Wrong mc_amount value: $f->{mc_gross}") 
		unless $f->{mc_gross}==$transaction->{amount};
	error("Wrong mc_currency value: $f->{mc_currency}") 
		unless lc $f->{mc_currency} eq lc $c->{currency_code};
	#error("Wrong receiver_email value: $f->{business}") 
	#  unless lc $f->{business} eq lc $c->{paypal_email};
	error("Wrong txn_id value: $f->{txn_id}") 
		unless $f->{txn_id};

	my $ua = LWP::UserAgent->new(agent => 'application/x-www-form-urlencoded', timeout => 90);
	my $data = [ map {$_=>$f->{$_}} %{$f} ];
	push @$data, 'cmd', '_notify-validate';
	my $res = $ua->post( $c->{paypal_url}, $data );
	print STDERR ("Got answer: ".$res->content);

	error( 'Error HTTP'  ) if $res->is_error;
	error( 'Transaction invalid'  ) unless lc $res->content eq 'verified';
	return($transaction);
}

1;
