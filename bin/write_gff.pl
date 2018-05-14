#!/usr/bin/env perl 
use warnings;
use strict;
use Data::Dumper;
use Apollo_fr;
use List::Util qw(min max);

#connect to the database
my $dbh = connect_to_iris_database('iris_genes');

#retrieve collapsed transcripts
my $collapsed_transcripts = retrieve_collapsed_transcripts($dbh);

#print GFF
open MASTER, '>', 'master.gff';
foreach my $transcript (keys %{$collapsed_transcripts}){
        my $scaffold = $collapsed_transcripts->{$transcript}{'scaffold'};
        my $strand =  $collapsed_transcripts->{$transcript}{'strand'};
        my $transcript_start = min (keys %{$collapsed_transcripts->{$transcript}{'exon_coords'}});
        my $last_transcript = max (keys %{$collapsed_transcripts->{$transcript}{'exon_coords'}});
        my $transcript_end = $collapsed_transcripts->{$transcript}{'exon_coords'}{$last_transcript};         
        print MASTER "$scaffold\tiris\tmRNA\t$transcript_start\t$transcript_end\t.\t$strand\t.\tID=$transcript;\n";
        my $i = 1;
        foreach my $exon (keys %{$collapsed_transcripts->{$transcript}{'exon_coords'}}){
        	my $end_coord = $collapsed_transcripts->{$transcript}{'exon_coords'}{$exon};
        	print MASTER "$scaffold\tiris\texon\t$exon\t$end_coord\t.\t$strand\t.\tID=$transcript.exon$i;parent=$transcript;\n";
 		$i++;
        } 
	$i = 1;
	foreach my $cds (keys %{$collapsed_transcripts->{$transcript}{'cds_coords'}}){
		my $end_coord = $collapsed_transcripts->{$transcript}{'cds_coords'}{$cds};
		print MASTER "$scaffold\tiris\tcds\t$cds\t$end_coord\t.\t$strand\t.\tID=$transcript.cds$i;parent=$transcript;\n";
		$i++;
	}
}
