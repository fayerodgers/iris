#!/usr/bin/env perl

use warnings;
use strict;
use Data::Dumper;
use POSIX qw(strftime);
use Getopt::Long;
use Apollo_fr;

my ($users, $annotations_path, $apollo_pword, $mysql_pword);
my $date = strftime "%F", localtime;

my $usage = "You need to provide the following options:\n
	--user_list - a file of user IDs to process (in the format avatar\@apollo).\n
	--annotations_path - the path to the directory where GFFs and FASTAs should be dumped.\n
	--apollo_pword - the admin password to Apollo.\n
	--mysql_pword - the password to the mysql server.\n 
";

GetOptions(
        'user_list=s' => \$users,
	'annotations_path=s' => \$annotations_path,
	'apollo_pword=s' => \$apollo_pword,
	'mysql_pword=s' => \$mysql_pword
) or die "$usage";

foreach my $option ($users, $annotations_path, $apollo_pword, $mysql_pword){ 
	unless (defined $option){ print $usage; die; }
}

my %all_users;
open USERS, '<', $users or die "can't open list of users";
while(<USERS>){
        chomp;
        if (/(.+)\@apollo/){
                my $user = $1;
                $all_users{$user} = ();
        }
        else{ die "can't parse user file"; }
}

#connect to the database and prepare sql statements
my $dbh = connect_to_iris_database('iris_genes', $mysql_pword);
my ($sth_populate_validated_transcripts, $sth_populate_validated_transcripts_cds, $sth_populate_validated_transcripts_exons, $sth_update_collapsed_ids, $sth_create_combined_transcript, $sth_create_combined_exons, $sth_create_combined_cds) = prepare_sql_statements($dbh, 'iris_genes');


#extract all transcripts from GFFs and database. Delete those transcripts that already exist in the database
my (%transcripts, %tokens);
my $transcripts = \%transcripts;
my $tokens = \%tokens;
foreach my $user (keys %all_users){
	my $gff = join "", $annotations_path, '/' ,$date,'/trichuris_trichiura_',$user,'.gff';
	($tokens, $transcripts) = parse_gff($user, $gff, $tokens, $transcripts);
}

%transcripts = %$transcripts;
#print Dumper \$validated_transcripts;
my $validated_transcripts = retrieve_validated_transcripts($dbh, 'all');
foreach my $user (keys %transcripts){
	foreach my $transcript (keys %{$transcripts{$user}}){
		if (exists $validated_transcripts->{$transcript}){ 
			delete $transcripts{$user}{$transcript};
			if (scalar keys %{$transcripts{$user}} == 0){ delete $transcripts{$user}; }
		 }
	}
}


#Validate all transcripts
my @users= keys %transcripts;
$transcripts = dump_FASTAs(\@users,\%transcripts,$apollo_pword,$annotations_path,$date);
%transcripts = %$transcripts;
my $introns_bed_file = './data/TTRE_all_introns.bed';
my $illumina_coverage_file = './data/coverage_blocks.bg';
my $isoseq_coverage_file = './data/isoseq_coverage_blocks.bg';
foreach my $user (keys %transcripts){
        my $peptide_fasta = join "",$annotations_path,'/',$date,'/trichuris_trichiura_',$user,'.peptide.fasta';
        my $t = validate_intron_boundaries($transcripts{$user},$introns_bed_file);
        $t = validate_coverage($t, $illumina_coverage_file, $isoseq_coverage_file);
        $t = validate_peptide($t, $peptide_fasta);
        $transcripts{$user} = $t;
}
#print Dumper \%transcripts;
#Put valid transcripts into the database
foreach my $user (keys %transcripts){
	TRANSCRIPT: foreach my $unique_transcript_id (keys $transcripts{$user}){
		foreach my $test ('C', 'I', 'IS', 'S', 'ST'){
			unless (exists $transcripts{$user}{$unique_transcript_id}{$test}){ next TRANSCRIPT; }
		}
		my $scaffold = $transcripts{$user}{$unique_transcript_id}{'scaffold'};
		my $strand = $transcripts{$user}{$unique_transcript_id}{'strand'};
		$sth_populate_validated_transcripts->execute($user,$unique_transcript_id,$scaffold,$strand);
		foreach my $cds (keys $transcripts{$user}{$unique_transcript_id}{'cds_coords'}){
			my $cds_start = $cds;
			my $cds_stop = $transcripts{$user}{$unique_transcript_id}{'cds_coords'}{$cds_start};
			my $frame = $transcripts{$user}{$unique_transcript_id}{'cds_frame'}{$cds_start};
			$sth_populate_validated_transcripts_cds->execute($unique_transcript_id, $cds_start,$cds_stop, $frame);
		}
		foreach my $exon (keys $transcripts{$user}{$unique_transcript_id}{'exon_coords'}){
			my $exon_start = $exon;
			my $exon_stop = $transcripts{$user}{$unique_transcript_id}{'exon_coords'}{$exon_start};
			$sth_populate_validated_transcripts_exons->execute($unique_transcript_id, $exon_start,$exon_stop);
		}	
	}
}


#Get transcripts not  assigned to a collapsed transcript
my $orphan_transcripts = retrieve_validated_transcripts($dbh,'orphans_only'); 
my %orphan_transcripts = %$orphan_transcripts;
#print Dumper \$orphan_transcripts;
#Get all collapsed transcripts
my $collapsed_transcripts = retrieve_collapsed_transcripts($dbh);
my %collapsed_transcripts = %$collapsed_transcripts;
#print Dumper \$collapsed_transcripts;
#Check if there is a collapsed transcript that they should be assigned to
foreach my $orphan_transcript (keys %orphan_transcripts){
	my $transcript_1 = $orphan_transcripts{$orphan_transcript};
	foreach my $collapsed_transcript (keys %collapsed_transcripts){
		if (defined $collapsed_transcripts{$collapsed_transcript}){
			my $transcript_2 = $collapsed_transcripts{$collapsed_transcript};
			$transcript_1 = compare_transcripts($transcript_1, $transcript_2);
		}
		if (exists $transcript_1->{'collapsed_id'}){
			$sth_update_collapsed_ids->execute($collapsed_transcript, $orphan_transcript);
			last;
		}
	}
	unless (exists $transcript_1->{'collapsed_id'}){
		$collapsed_transcripts{$orphan_transcript} = $orphan_transcripts{$orphan_transcript};
		$sth_create_combined_transcript->execute($orphan_transcript,$transcript_1->{'scaffold'}, $transcript_1->{'strand'} );
		$sth_update_collapsed_ids->execute($orphan_transcript, $orphan_transcript);
		foreach my $cds (keys %{$transcript_1->{'cds_coords'}}){
			$sth_create_combined_cds->execute($orphan_transcript, $cds, $transcript_1->{'cds_coords'}{$cds}, $transcript_1->{'cds_frame'}{$cds});
		}
		foreach my $exon (keys %{$transcript_1->{'exon_coords'}}){
			$sth_create_combined_exons->execute($orphan_transcript, $exon, $transcript_1->{'exon_coords'}{$exon});
		}
	}
} 

#print Dumper \%collapsed_transcripts;
#print Dumper \%orphan_transcripts;

#Reconcile UTRs
$collapsed_transcripts = retrieve_collapsed_transcripts($dbh);
#print Dumper \$collapsed_transcripts;
foreach my $collapsed_id (keys %{$collapsed_transcripts}){
	if (scalar keys %{$collapsed_transcripts{$collapsed_id}{'unique_ids'}} > 1){
		reconcile_utrs($collapsed_id, $dbh);
	}
}

#Allocate transcripts to parent genes
assign_transcripts_to_genes($collapsed_transcripts,$dbh);



