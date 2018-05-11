#!/usr/bin/env perl
use strict;
use warnings;
use HTTP::Tiny;
use Data::Dumper;
use JSON;
use Getopt::Long;

#print a list of IRIS user accounts in Apollo.

my ($username, $server, $apollo_pword, @usernames);

my $usage = "You need to provide the following options:\n
	--apollo_admin_user\n
	--apollo_url\n
	--apollo_pword\n
";

GetOptions(
	'apollo_admin_user=s' => \$username,
	'apollo_url=s' => \$server,
	'apollo_pword=s' => \$apollo_pword,
) or die "$usage";

foreach my $argument ($username, $server, $apollo_pword){
	unless (defined $argument) { die "$usage"; }
}

my %options = ('timeout' => 500);
my $http = HTTP::Tiny->new(%options);
$server = $server.'/user/loadUsers';

my $response = $http->request('POST',$server, {
	headers => {'Content-type' => 'application/json'},
	content => "{'omitEmptyOrganisms': 'true', 'username': ".$username.", 'password': ".$apollo_pword."}"
});

#print Dumper \$response, "\n";
die "Failed!\n" unless $response->{success};

if (length $response->{content}){
	my $accounts = decode_json($response->{content});
#	print Dumper \$accounts, "\n";
	foreach my $account (@$accounts){
		my $username = $account->{'username'};
		if ($username =~ /\@apollo/){
			push @usernames, $username;
		}
	}
}

print join("\n",@usernames);
