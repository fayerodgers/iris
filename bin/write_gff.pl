#!/usr/bin/env perl 
use warnings;
use strict;
use Data::Dumper;
use FindBin qw($Bin);
use lib "$Bin";
use Apollo_fr;
use List::Util qw(min max);
use Getopt::Long;

my ($mysql_pword, $output_dir);
my $usage = "You need to provide --mysql_pword and --output_directory \n";
GetOptions(
	'mysql_pword=s' => \$mysql_pword,
	'output_directory=s' => \$output_dir
) or die "$usage";

foreach my $argument ($mysql_pword, $output_dir){
	unless (defined $argument) {die "$usage"; }
}
#connect to the database
my $dbh = connect_to_iris_database('iris_genes',$mysql_pword);

#retrieve collapsed transcripts
my $collapsed_transcripts = retrieve_collapsed_transcripts($dbh);
my $genes = retrieve_genes($dbh);
$dbh->disconnect;

#print GFF
open MASTER, '>', $output_dir.'/master.gff';

foreach my $gene (keys %{$genes}){
	my $scaffold = $genes->{$gene}{'scaffold'};
	my $strand = $genes->{$gene}{'strand'};	
	my $start = $genes->{$gene}{'start'};
	my $end = $genes->{$gene}{'end'};
	print MASTER "$scaffold\tiris\tgene\t$start\t$end\t.\t$strand\t.\tID=TTRE$gene;\n";
	foreach my $transcript (@{$genes->{$gene}{'transcripts'}}){
		my $transcript_start = min (keys %{$collapsed_transcripts->{$transcript}{'exon_coords'}});
		my $last_transcript = max (keys %{$collapsed_transcripts->{$transcript}{'exon_coords'}});
		my $transcript_end = $collapsed_transcripts->{$transcript}{'exon_coords'}{$last_transcript};
		print MASTER "$scaffold\tiris\tmRNA\t$transcript_start\t$transcript_end\t.\t$strand\t.\tID=$transcript;Parent=TTRE$gene;\n";
		my $i = 1;
        	foreach my $exon (keys %{$collapsed_transcripts->{$transcript}{'exon_coords'}}){
                	my $end_coord = $collapsed_transcripts->{$transcript}{'exon_coords'}{$exon};
                	print MASTER "$scaffold\tiris\texon\t$exon\t$end_coord\t.\t$strand\t.\tID=$transcript.exon$i;Parent=$transcript;\n";
                	$i++;
       		}
        	$i = 1;
        	foreach my $cds (keys %{$collapsed_transcripts->{$transcript}{'cds_coords'}}){
                	my $end_coord = $collapsed_transcripts->{$transcript}{'cds_coords'}{$cds};
                	print MASTER "$scaffold\tiris\tcds\t$cds\t$end_coord\t.\t$strand\t.\tID=$transcript.cds$i;Parent=$transcript;\n";
                	$i++;
        	}
	}
}

close MASTER;

