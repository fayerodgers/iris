#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use DBD::mysql;
use POSIX qw(strftime);
use Data::Dumper;
use Getopt::Long;
use Apollo_fr;

my ($new_users, $mysql_pword, %users);

my $usage = "You need to provide the following arguments:\n
	--new_users - a list of avatars to add to the database (in the format avatar\@apollo)\n
	--mysql_pword\n
";

GetOptions(
	'new_users=s' => \$new_users,
	'mysql_pword=s' => \$mysql_pword
) or die "$usage";

foreach my $argument ($new_users, $mysql_pword){
	unless (defined $argument) { die "$usage";}
}

open USERS, '<', $new_users or die "couldn't open new_users file \n";

my $date = strftime "%F", localtime;
my $dbh = connect_to_iris_database('iris_tokens', $mysql_pword);
my ($sth_allocate_tokens, $sth_reallocate_tokens, $sth_get_allocated_tokens, $sth_update_token_outcomes, $sth_update_transcript_outcomes, $sth_get_event_id)  = prepare_sql_statements($dbh, 'iris_tokens');

while (<USERS>){
	chomp;
	if (/((.+)_.+)\@apollo/){
		my $avatar = $1;
		my $school = $2;
		$users{$avatar}{'school'} = $school;	
	}
	else{ die "Can't parse new_users file\n"; }
}

add_users_to_iris_tokens(\%users,$date,$dbh);
my $all_tokens = retrieve_token_data($dbh);
allocate_tokens($sth_allocate_tokens, \%users, $all_tokens, $date);

