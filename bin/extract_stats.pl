#!/usr/bin/env perl 
use warnings;
use strict;
use Data::Dumper;
use List::Util;
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin";
use Apollo_fr;

my ($mysql_pword, $output_dir);
my $usage = "You need to provide --mysql_pword and --output_directory \n";
GetOptions(
	'mysql_pword=s' => \$mysql_pword,
	'output_directory=s' => \$output_dir
) or die "$usage";

foreach my $argument ($mysql_pword, $output_dir){
	unless (defined $argument) {die "$usage"; }
}

open COVERAGE, '>', $output_dir.'/coverage.txt';
open SCHOOLS, '>', $output_dir.'/schools.txt';
open STUDENTS, '>', $output_dir.'/students.txt';

#connect to the database
my $dbh_genes = connect_to_iris_database('iris_genes', $mysql_pword);
my $dbh_tokens = connect_to_iris_database('iris_tokens', $mysql_pword);

#retrieve collapsed transcripts
my $collapsed_transcripts = retrieve_collapsed_transcripts($dbh_genes);
my $users = retrieve_all_users_from_db($dbh_tokens);
my $validated_transcripts = retrieve_validated_transcripts($dbh_genes,'all');

#print a file showing number of transcripts with a coverage of x
my %coverage;
foreach my $transcript (keys %{$collapsed_transcripts}){
	my $coverage = scalar keys %{$collapsed_transcripts->{$transcript}{'unique_ids'}};
	$coverage{$coverage}++;
}

foreach my $coverage (sort { $a <=> $b } keys %coverage){
	print COVERAGE "$coverage\t$coverage{$coverage}\n";
}

#print a file with the number of valid transcripts per school
my %schools;
my %students;

foreach my $student (keys %$users){
	$students{$student} = 0;
	my $school = $users->{$student}{'school'};
	$schools{$school} = 0;
}

foreach my $transcript (keys %{$validated_transcripts}){
	my $student = $validated_transcripts->{$transcript}{'avatar'};
	my $school = $users->{$student}{'school'};
	$schools{$school}++;
	$students{$student}++;
}

foreach my $school (keys %schools){
	print SCHOOLS "$school\t$schools{$school}\n";
}

foreach my $student (keys %students){
	print STUDENTS "$student\t$students{$student}\n";
}	

