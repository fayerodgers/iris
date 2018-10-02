#!/usr/bin/env perl
use strict;
use warnings;
use HTTP::Tiny;
use Data::Dumper;
use JSON;
use Getopt::Long;

my ($username, $apollo_pword, $species, $directory, $genus, $common_name);

my $usage = "You need to provide the following options:\n
	--username\n
	--apollo_pword\n
	--species\n
	--genus\n
	--data_directory\n
	--common_name\n
";

GetOptions(
	'username=s' => \$username,
	'apollo_pword=s' => \$apollo_pword,
	'species=s' => \$species,
	'genus=s' => \$genus,
	'data_directory=s' => \$directory,
	'common_name=s' => \$common_name 
) or die "$usage";

foreach my $argument ($username, $apollo_pword, $species, $directory, $genus, $common_name){
	unless (defined $argument){die "$usage"; }
}

my %options = ('timeout' => 500);
my $http = HTTP::Tiny->new(%options);
my $server = 'http://apollo.wormbase.org/';
my $ext = 'organism/addOrganism';

my $response = $http->request('POST',$server.$ext, {
	headers => {'Content-type' => 'application/json'},
	content => "{'username': ".$username.", 'password': ".$apollo_pword.", 'directory': ".$directory.", 'species' : ".$species.", 'genus' : ".$genus.", 'commonName' : ".$common_name."}"
});

print Dumper \$response, "\n";
unless ($response->{success}){
	print Dumper \$response;
	die "Failed!\n";
}


