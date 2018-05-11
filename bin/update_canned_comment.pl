#!/usr/bin/env perl
use strict;
use warnings;
use HTTP::Tiny;
use Data::Dumper;
use Getopt::Long;

my ($username, $server, $apollo_pword, $old_comment, $new_comment);

my $usage = "You need to provide the following options:\n
	--apollo_admin_user\n
	--apollo_url\n
	--apollo_pword\n
	--old_comment\n
	--new_comment\n
";

GetOptions(
	'apollo_admin_user=s' => \$username,
	'apollo_url=s' => \$server,
	'apollo_pword=s' => \$apollo_pword,
	'old_comment' => \$old_comment,
	'new_comment' => \$new_comment,
) or die "$usage";

foreach my $argument ($username, $server, $apollo_pword, $old_comment, $new_comment){
	unless (defined $argument) { die "$usage"; }
}

my %options = ('timeout' => 500);
my $http = HTTP::Tiny->new(%options);
my $server = $server.'cannedComment/updateComment';

my $response = $http->request('POST',$server, {
	headers => {'Content-type' => 'application/json'},
	content => "{'username': ".$username.", 'password': ".$apollo_pword.", 'old_comment' : ".$old_comment.", 'new_comment' : ".$new_comment." }"
});

print Dumper \$response;
die "Failed!\n" unless $response->{success};
