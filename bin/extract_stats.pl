#!/usr/bin/env perl 
use warnings;
use strict;
use Data::Dumper;
use Apollo_fr;
use List::Util;

open COVERAGE, '>', 'coverage.txt';
open SCHOOLS, '>', 'schools.txt';
open STUDENTS, '>', 'students.txt';

#connect to the database
my $dbh_genes = connect_to_iris_database('iris_genes');
my $dbh_tokens = connect_to_iris_database('iris_tokens');

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

