# Base class for Payments plugin
package Payments;
use strict;
use XFileConfig;

sub get_config_fields {
	# Extract the config fields required from $self->options 
	my @s_fields = @{ $_[0]->options->{s_fields} };
	return( map { $_->{name} } @s_fields );
}

sub get_admin_settings {
	# Format $self->options to be understandeable by admin_settings.html
	return if ref($_[0]->options->{s_fields}) ne 'ARRAY';

	my @s_fields = @{ $_[0]->options->{s_fields} };
	for(@s_fields) {
		$_->{"type_$_->{type}"} = 1;
		$_->{value} = $c->{$_->{name}};
	}
	return(@s_fields);
}

sub get_payment_buy_with {
	# Format $self->options to be understandeable by payment_buy_with.html
	return undef if !$c->{$_[0]->options->{account_field}};
	return($_[0]->options);
}


1;
