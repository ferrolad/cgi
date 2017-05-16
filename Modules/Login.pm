package Login;
use JSON;
use Data::Dumper qw(Dumper);
# Base class for Plugins/Login/.*

sub is_can_applied {
	# Helper utility
	my ($plg_name, $f) = @_;
	return if !$f->{method};

	# Decide if the method can be applied depending on it's module name
	my $method = $1 if $plg_name =~ /::(\w+)$/;
	return 1 if $method eq $f->{method};
}

sub get_auth_url {
	# Step 1: get a redirect URL
	my ($plg_name, $f) = @_;
	return if !&is_can_applied(@_);

	# It's expected that the plugin defines an OAuth2 object.
	# Otherwise, it should override this method.
	my $oauth = ${ $plg_name . '::oauth' };
	die("oauth is not defined for $plg_name") if !$oauth;

	return $oauth->authorize;
}

sub finish {
	# Step 2: return the user data once authorization is complete
	# A hashref with the following fields defined should be returned:
	# 	usr_social_id
	#	usr_login
	#	usr_email
	my ($plg_name, $f) = @_;
	return if !&is_can_applied(@_);

	my $access = ${ $plg_name . '::oauth' }->get_access_token($f->{code});
	my $oauth_ret = JSON::decode_json($access->get(${ $plg_name . '::userinfo_url' })->decoded_content);

	my %result_fields = %{ $plg_name . '::result_fields' };
	die("result_fields is not defined for $plg_name") if !%result_fields;

	# Mapping $oauth_ret to $ret
	my $ret;
	for(keys(%result_fields)) {
		$ret->{$_} = $oauth_ret->{$result_fields{$_}};
	}
	return($ret);
}

1;
