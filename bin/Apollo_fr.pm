#!/usr/bin/env perl
package Apollo_fr;
use warnings;
use strict;
use base 'Exporter';
our @EXPORT = qw(parse_gff validate_intron_boundaries validate_coverage validate_cds validate_peptide connect_to_iris_database prepare_sql_statements retrieve_all_users_from_db retrieve_token_data retrieve_token_data_v2 allocate_tokens allocate_tokens_v2 retrieve_validated_transcripts dump_FASTAs retrieve_orphan_transcripts retrieve_collapsed_transcripts compare_transcripts reconcile_utrs assign_transcripts_to_genes apollo_dump delete_feature add_users_to_iris_tokens retrieve_genes delete_all_features);
use Data::Dumper;
use DBI;
use DBD::mysql;
use HTTP::Tiny;
use List::Util qw(min max);


#####################################

sub parse_gff{
	my ($user, $gff, $tokens, $transcripts)= @_;
	my $valid = 0;
	my %tokens = %$tokens;
	my %transcripts = %$transcripts;
	open GFF ,'<', $gff or die "failed to open $gff";
	my %gene_data;
	while (<GFF>){
		
		if (/##gff-version 3/){ $valid = 1;}
    		my @temp = split /\t/, $_;
       		if (/repeat_region/){
            		if (/(?:Note=(.[^;]+))?;ID=(.[^;]+);date_last_modified=(.+);Name=Token_([0-9]+)/){
               			my $unique_token_id = $2;
               			my %token_data = (
            				'name' => $4,
           				'scaffold' => $temp[0],
           				'start' => $temp[3],
            				'end' => $temp[4],
        				);  
              			if (defined $1) {
                   			if ($1 =~ /Reject token- too complex/) {
                   			$token_data{'rejection'} = 'complex';
                  	 	}
                   		elsif ($1 =~ /Please check this token manually/) {
 		 			$token_data{'rejection'} = 'manual_check';                
                   		}
              		}
          		$tokens{$user}{$unique_token_id} = \%token_data;
      	     		}
       		}
		elsif (/\tgene\t/ && /(?:;Note=(.[^;]+))?(?:;description=(.[^;]+))?;ID=(.[^;]+)/){
			my $gene_id = $3;
			if (defined $1){$gene_data{$gene_id}{'note'} = $1;}
			if (defined $2){$gene_data{$gene_id}{'other_avatars'} = $2;}
		}	
		elsif (/\tmRNA\t/ && /owner=(.+);Parent=(.[^;]+)(?:;Note=(.[^;]+))?(?:;description=(.[^;]+))?;ID=(.[^;]+);date_last_modified=(.+);Name=(.[^;]+)/){
			my $unique_transcript_id = $5;
			my %transcript_data = (
				'name' => $7,
				'parent' => $2,
				'scaffold' => $temp[0],
				'start' => $temp[3],
				'end' => $temp[4],
				'strand' => $temp[6]
			);
			if (defined $3){
				if ($3 =~ /No evidence for this gene/){
					$transcript_data{'NE'} = ();
				}
				else {$transcript_data{'note'} = $3;} 
			}
			if (defined $4){
				$transcript_data{'other_avatars'} = $4; 
			}
			my $owner = $1;
			if ($owner =~/(.+)\@apollo/ ){$transcript_data{'owner'} = $1; }
			else {$transcript_data{'owner'} = $user; } 
			$transcripts{$user}{$unique_transcript_id} = \%transcript_data;	
		}
		elsif (/\texon\t/ && /Parent=(.*);ID=/){
			my $unique_transcript_id = $1;
			$transcripts{$user}{$unique_transcript_id}{'exon_coords'}{$temp[3]} = $temp[4]; 
		}
		elsif (/\tCDS\t/ && /Parent=(.[^;]+);/){
			my $unique_transcript_id = $1;
			$transcripts{$user}{$unique_transcript_id}{'cds_coords'}{$temp[3]} = $temp[4];
			my $rf;
			if ($temp[6] eq '+'){
				$rf = ($temp[3]+$temp[7])%3; #(cds start position + phase) % 3
			}
			elsif ($temp[6] eq '-'){
				$rf = ($temp[4]-$temp[7])%3;
			}
			$transcripts{$user}{$unique_transcript_id}{'cds_frame'}{$temp[3]} = $rf;
		}
	}
	foreach my $unique_transcript_id (keys %{$transcripts{$user}}){
		my $cds_start = min(keys %{$transcripts{$user}{$unique_transcript_id}{'cds_coords'}});
		my $c = max(keys %{$transcripts{$user}{$unique_transcript_id}{'cds_coords'}});
		my $cds_end = $transcripts{$user}{$unique_transcript_id}{'cds_coords'}{$c};
		if ($cds_end - $cds_start >= 6){	#later need to delete genes with a backwards CDS or a CDS < 1 aa. Would break FASTA dumping.
			$transcripts{$user}{$unique_transcript_id}{'cds'} = 'valid';
		}
		my $gene_id = $transcripts{$user}{$unique_transcript_id}{'parent'};
		if (defined $gene_data{$gene_id}{'note'}){
			$transcripts{$user}{$unique_transcript_id}{'note'} .= $gene_data{$gene_id}{'note'};
		}
		if (defined $gene_data{$gene_id}{'other_avatars'}){
			$transcripts{$user}{$unique_transcript_id}{'other_avatars'} .= $gene_data{$gene_id}{'other_avatars'};
		}
	}
	return (\%tokens, \%transcripts);
}

###########################################


sub validate_intron_boundaries{
	my ($transcripts, $introns_bed_file) = @_;
	open INTRONS, '<', $introns_bed_file or die "can't open introns file";
	my %illumina_introns;
	while (<INTRONS>){	
	        my @temp = split /\t/, $_;
        	my $scaffold = $temp[0];
		my $intron_end = $temp[2] + 1;
		my $intron = join ("..", $temp[1], $intron_end);
		$illumina_introns{$scaffold}{$intron} = ();
	} 
	my %transcripts = %$transcripts;
	foreach my $transcript (keys %transcripts){
		my @sorted_exon_starts = sort {$a <=> $b} (keys %{$transcripts{$transcript}->{'exon_coords'}});
		my $exon_count = scalar @sorted_exon_starts;
		if ($exon_count == 1){  #don't apply test if transcript has only one exon
			$transcripts{$transcript}{'I'} = 'valid';
			next;
		}
		my $scaffold = $transcripts{$transcript}->{'scaffold'}; 
		my $i = 0;
		my $x = 0;
		foreach my $exon_a (@sorted_exon_starts){
			$i++;
			my $exon_a_end = $transcripts{$transcript}->{'exon_coords'}{$exon_a};
			my $exon_b_start = $sorted_exon_starts[$i];
			my $intron = $exon_a_end.'..'.$exon_b_start;
			foreach my $illumina_intron (keys %{$illumina_introns{$scaffold}}){
				if ($illumina_intron eq $intron){
					$x++; last;
				}											
			}	
			if ($i == ($exon_count-1)){ last; }
		}
		if ($x == ($exon_count-1)){
			$transcripts{$transcript}{'I'}= 'valid';
		} 
	}
	return \%transcripts;
}

#####################################
sub validate_coverage{
	my ($transcripts, $illumina_coverage_file, $isoseq_coverage_file) = @_;
	open ILLUMINA_COVERAGE, '<', $illumina_coverage_file or die "can't open Illumina coverage file";
	open ISOSEQ_COVERAGE, '<', $isoseq_coverage_file or die "can't open Isoseq coverage file";
	my %illumina_coverage;
	my %isoseq_coverage;
	while (<ILLUMINA_COVERAGE>){
		chomp;
		my @temp = split /\t/, $_;
		my $scaffold = $temp[0];
		my $block_start = $temp[1];
		my $block_end = $temp[2];
		$illumina_coverage{$scaffold}{$block_start} = $block_end;	
	}
	while (<ISOSEQ_COVERAGE>){
		my @temp = split /\t/, $_;
		my $scaffold = $temp[0];
		my $block_start = $temp[1];
		my $block_end = $temp[2];
		$isoseq_coverage{$scaffold}{$block_start} = $block_end;
	}
	my %transcripts = %$transcripts;
	foreach my $transcript (keys %transcripts){
		$transcripts{$transcript}{'C'} = 'valid';
		my $scaffold = $transcripts{$transcript}->{'scaffold'};
		EXON: foreach my $exon_start (keys $transcripts{$transcript}->{'exon_coords'}){
			my $exon_end = $transcripts{$transcript}->{'exon_coords'}{$exon_start};
			foreach my $block_start (keys %{$illumina_coverage{$scaffold}}){
				if ($exon_start >= $block_start && $exon_start <= $illumina_coverage{$scaffold}{$block_start}){
					if ($exon_end >= $block_start && $exon_end <= $illumina_coverage{$scaffold}{$block_start}){
						last EXON;
					}
				}
			}
			foreach my $block_start (keys %{$isoseq_coverage{$scaffold}}){
                                if ($exon_start >= $block_start && $exon_start <= $isoseq_coverage{$scaffold}{$block_start}){
                                        if ($exon_end >= $block_start && $exon_end <= $isoseq_coverage{$scaffold}{$block_start}){
                                                last EXON;
                                        }
                                }
			}
			if (exists $transcripts{$transcript}{'C'} ){ delete $transcripts{$transcript}{'C'}; }		
		}	
	}
	return \%transcripts;
}

#####################################
sub validate_cds{
	my ($transcripts, $cds_fasta) = @_;
	open CDS_FASTA, '<', $cds_fasta or die "can't open $cds_fasta\n";
	my %transcripts = %$transcripts; 
	my (%cds, $transcript);
	while (<CDS_FASTA>){
		if (/>(.+) \(mRNA\)/){
			$transcript = $1;
		}
		else{
			chomp;
			$cds{$transcript} .= $_;
		}
	}
	foreach my $transcript (keys %cds){
	#	print "$transcript\t";
		my $stop = substr $cds{$transcript}, -3;
		next unless exists $transcripts{$transcript};
	#	print "$stop\n";
		if (($stop eq 'TAA') || ($stop eq 'TGA') || ($stop eq 'TAG')){
			$transcripts{$transcript}{'S'} = 'valid';
		}
	}	
	return \%transcripts;
}

#####################################
sub validate_peptide{
	my ($transcripts, $peptide_fasta) = @_;
	#print "$peptide_fasta\n";
	open PEPTIDE_FASTA, '<', $peptide_fasta or die "can't open $peptide_fasta\n";
	my %transcripts = %$transcripts;
	my (%peptide, $transcript);
	while(<PEPTIDE_FASTA>){
		if (/>(.+) \(mRNA\)/){
			$transcript = $1;
		}
		else{
			chomp;
			$peptide{$transcript} .= $_;
		}
	}
	#print Dumper \%peptide;
	foreach my $transcript (keys %peptide){
		if ($peptide{$transcript} =~ /^M/){
			$transcripts{$transcript}{'ST'} = 'valid';
		}
		unless ($peptide{$transcript} =~ /\*/){
			$transcripts{$transcript}{'IS'} = 'valid';
		}
	}
	return \%transcripts;
}


1;
#####################################
sub connect_to_iris_database{
	my ($database, $password) = @_;
        my $host = 'mysql-wormbase-pipelines';
        my $port = '4331';
        my $userid = 'wormadmin';
        my $dsn = "dbi:mysql:dbname=$database;host=$host;port=$port;";
        my $dbh = DBI->connect($dsn, $userid, $password);
	return $dbh;
}

####################################
#expects a hash of transcripts in the format produced by parse_gff and a list of users for whom the FASTAs should be dumped.
sub dump_FASTAs{
	my ($users, $transcripts, $apollo_pword, $annotations_path, $date) = @_;
	my %transcripts = %$transcripts;
	my @users= @$users;
	foreach my $user (@users){
		my $organism = join "", 'trichuris_trichiura_', $user; 
		next unless (exists $transcripts{$user});
		foreach my $unique_transcript_id (keys %{$transcripts{$user}}){
			unless (exists $transcripts{$user}{$unique_transcript_id}{'cds'}){ #'cds' exists if the cds is in the correct orientation in the gff (according to parse_gff)
				print STDERR "Deleting $unique_transcript_id for user $user - invalid CDS \n";
				delete_feature($organism,$unique_transcript_id,$apollo_pword);
				sleep(5);
				delete $transcripts{$user}{$unique_transcript_id};
			}
		}
		unless (-f $annotations_path.'/'.$date.'/'.$organism.'.cds.fasta'){
     			apollo_dump($organism, $apollo_pword, 'cds.fasta', $annotations_path, $date);
			sleep(5);
		}
                unless (-f $annotations_path.'/'.$date.'/'.$organism.'.peptide.fasta'){
                        apollo_dump($organism, $apollo_pword, 'peptide.fasta', $annotations_path, $date);
                        sleep(5);
		}
	}
}


#####################################
sub prepare_sql_statements{
	my ($dbh,$database) = @_;
	if ($database eq 'iris_tokens'){
		my $sth_allocate_tokens = $dbh->prepare('INSERT INTO allocated_tokens (token_id, avatar, date_out) VALUES (?,?,?)');
		my $sth_reallocate_tokens = $dbh->prepare('INSERT INTO allocated_tokens (token_id, avatar, date_out,previous_event_id) VALUES (?,?,?,?)');
		my $sth_get_allocated_tokens = $dbh->prepare('SELECT avatar,token_id,outcome,date_returned FROM allocated_tokens');
		my $sth_update_token_outcomes = $dbh->prepare('UPDATE allocated_tokens SET outcome = ?, date_returned = ? WHERE token_id = ? AND avatar = ? and outcome is NULL');
		my $sth_update_transcript_outcomes = $dbh->prepare('INSERT INTO nonvalidated_transcripts (event_id, transcript_id, transcript_name, test_outcomes) VALUES (?,?,?,?)');
		my $sth_get_event_id = $dbh->prepare('SELECT event_id FROM allocated_tokens WHERE token_id = ? AND avatar = ? AND date_returned = ?');
		return ($sth_allocate_tokens, $sth_reallocate_tokens, $sth_get_allocated_tokens, $sth_update_token_outcomes, $sth_update_transcript_outcomes, $sth_get_event_id);
	}
	if ($database eq 'iris_genes'){
		my $sth_populate_validated_transcripts = $dbh->prepare('INSERT INTO validated_transcripts (avatar, unique_id, scaffold, strand) VALUES (?,?,?,?)');
        	my $sth_populate_validated_transcripts_cds = $dbh->prepare('INSERT INTO validated_transcripts_cds (unique_id, start_cds, stop_cds, frame) VALUES (?,?,?,?)');
        	my $sth_populate_validated_transcripts_exons = $dbh->prepare('INSERT INTO validated_transcripts_exons (unique_id, start_exon, stop_exon) VALUES (?,?,?)');
        	my $sth_update_collapsed_ids = $dbh->prepare('UPDATE validated_transcripts SET collapsed_id = ? WHERE unique_id = ?');
        	my $sth_create_combined_transcript = $dbh->prepare('INSERT INTO combined_ids (collapsed_id,scaffold,strand) VALUES (?,?,?)');
        	my $sth_create_combined_exons = $dbh->prepare('INSERT INTO combined_exons (collapsed_id,start_exon,stop_exon) VALUES (?,?,?)');
        	my $sth_create_combined_cds = $dbh->prepare('INSERT INTO combined_cds (collapsed_id, start_cds, stop_cds, frame) VALUES (?,?,?,?)');
		my $sth_populate_multi_transcripts = $dbh->prepare('INSERT INTO multi_owned_transcripts (avatar, unique_id) VALUES (?,?)');
		return ($sth_populate_validated_transcripts, $sth_populate_validated_transcripts_cds, $sth_populate_validated_transcripts_exons, $sth_update_collapsed_ids, $sth_create_combined_transcript, $sth_create_combined_exons, $sth_create_combined_cds, $sth_populate_multi_transcripts);
	}
}



#####################################
sub retrieve_all_users_from_db{
	my $dbh = shift;
	my $sth = $dbh->prepare('SELECT students.school, students.avatar, allocated_tokens.token_id,  allocated_tokens.outcome FROM students LEFT JOIN allocated_tokens ON students.avatar = allocated_tokens.avatar');
	my %users;
	$sth->execute();
	while (my @users_db = $sth->fetchrow_array){
		my $school = $users_db[0];
		my $avatar = $users_db[1];
		$users{$avatar}{'school'} = $school;
		if (defined $users_db[2]){
			my $token = $users_db[2];
			if (defined $users_db[3]){
				my $outcome = $users_db[3];
				if ($outcome =~ /^validated/){
					$users{$avatar}{'validated_tokens'}{$token} = ();
				}
			}
			else{
				$users{$avatar}{'current_tokens'}{$token} = ();
			}
			$users{$avatar}{'all_tokens'}{$token} = ();
		}
	}
	return \%users;
}

#####################################
sub add_users_to_iris_tokens{
	my ($users, $date, $dbh) = @_;
	my %users = %$users;
	my $sth = $dbh->prepare('INSERT INTO students (avatar, school, date_last_checked) values (?,?,?)');
	foreach my $user (keys %users){
		$sth->execute($user,$users{$user}{'school'},$date);
	}
}

######################################
sub retrieve_token_data{
	my $dbh = shift;
	my $sth = $dbh->prepare('SELECT tokens.token_id, tokens.aggregate_score, allocated_tokens.avatar FROM tokens LEFT JOIN allocated_tokens ON tokens.token_id = allocated_tokens.token_id');
	$sth->execute();
	my %tokens;
	while (my @tokens_db = $sth->fetchrow_array){
		if (defined $tokens_db[2]){
			$tokens{$tokens_db[0]}++;
		}
		else{$tokens{$tokens_db[0]} =0; }
	}
	return \%tokens;
}

######################################
sub retrieve_token_data_v2{
	my $dbh = shift;
	my $sth = $dbh->prepare('SELECT aggregate_score, token_id, isoseq_score, iris_score FROM tokens');
	$sth->execute();
	my %tokens;
	while (my @tokens_db = $sth->fetchrow_array){
		$tokens{'aggregate_score'}{$tokens_db[1]}=$tokens_db[0];
		if ($tokens_db[3] == 0){
			$tokens{'iso_score'}{$tokens_db[1]}=$tokens_db[2];
		}
		else{
			$tokens{'iso_score'}{$tokens_db[1]}=0;
		}
	}
	return \%tokens;	
}



#######################################
sub retrieve_collapsed_transcripts{
	my $dbh = shift;
	my $sth = $dbh->prepare('SELECT combined_ids.collapsed_id, combined_ids.scaffold, combined_ids.parent_gene, combined_cds.start_cds, combined_cds.stop_cds, combined_exons.start_exon, combined_exons.stop_exon, validated_transcripts.unique_id, combined_ids.strand, combined_cds.frame FROM combined_ids LEFT JOIN combined_cds ON combined_ids.collapsed_id = combined_cds.collapsed_id LEFT JOIN combined_exons ON combined_ids.collapsed_id = combined_exons.collapsed_id LEFT JOIN validated_transcripts ON combined_ids.collapsed_id = validated_transcripts.collapsed_id');
	$sth->execute();
	my %collapsed_transcripts;
	while (my @db_transcripts = $sth->fetchrow_array){
		my $collapsed_id = $db_transcripts[0];
		$collapsed_transcripts{$collapsed_id}{'scaffold'} = $db_transcripts[1];
		$collapsed_transcripts{$collapsed_id}{'parent_gene'} = $db_transcripts[2];
		$collapsed_transcripts{$collapsed_id}{'cds_coords'}{$db_transcripts[3]} = $db_transcripts[4];
		$collapsed_transcripts{$collapsed_id}{'cds_frame'}{$db_transcripts[3]} = $db_transcripts[9];
		$collapsed_transcripts{$collapsed_id}{'exon_coords'}{$db_transcripts[5]} = $db_transcripts[6];
		$collapsed_transcripts{$collapsed_id}{'unique_ids'}{$db_transcripts[7]}=();
		$collapsed_transcripts{$collapsed_id}{'strand'} = $db_transcripts[8];
	}
	return \%collapsed_transcripts;
}

##########################################
sub retrieve_genes{
	my $dbh = shift;
	my %genes;
	my $sth_all_genes = $dbh->prepare('SELECT DISTINCT parent_gene FROM combined_ids');
	$sth_all_genes->execute();
	my $sth = $dbh->prepare('SELECT combined_ids.collapsed_id, combined_ids.strand, combined_ids.scaffold, MIN(combined_exons.start_exon), MAX(combined_exons.stop_exon) FROM combined_ids LEFT JOIN combined_exons ON combined_ids.collapsed_id = combined_exons.collapsed_id WHERE combined_ids.parent_gene = ?');
	while (my @db_genes = $sth_all_genes->fetchrow_array){
		my $gene = $db_genes[0];
		$sth->execute($gene);
		while (my @db_gene_data = $sth->fetchrow_array){
			push @{$genes{$gene}{'transcripts'}}, $db_gene_data[0];
			$genes{$gene}{'strand'} = $db_gene_data[1];
			$genes{$gene}{'scaffold'} = $db_gene_data[2];
			$genes{$gene}{'start'} = $db_gene_data[3];
			$genes{$gene}{'end'} = $db_gene_data[4];
		}
	}
	return \%genes;
}


##########################################
sub retrieve_validated_transcripts{
	my ($dbh,$orphans) = @_;
	my $sql = 'SELECT validated_transcripts.unique_id, validated_transcripts.scaffold, validated_transcripts.strand, validated_transcripts_cds.start_cds, validated_transcripts_cds.stop_cds, validated_transcripts_exons.start_exon, validated_transcripts_exons.stop_exon, validated_transcripts.avatar, validated_transcripts_cds.frame FROM validated_transcripts LEFT JOIN validated_transcripts_cds ON validated_transcripts.unique_id = validated_transcripts_cds.unique_id LEFT JOIN validated_transcripts_exons ON validated_transcripts.unique_id = validated_transcripts_exons.unique_id';
	if ($orphans eq 'orphans_only'){
		$sql = $sql.' WHERE collapsed_id IS NULL';
	}
	my $sth = $dbh->prepare($sql);
	$sth->execute();
	my %validated_transcripts;
	while (my @db = $sth->fetchrow_array){
		my $unique_id = $db[0];
		$validated_transcripts{$unique_id}{'scaffold'} = $db[1];
		$validated_transcripts{$unique_id}{'strand'} = $db[2];
		$validated_transcripts{$unique_id}{'cds_coords'}{$db[3]} = $db[4];
		$validated_transcripts{$unique_id}{'cds_frame'}{$db[3]} = $db[8];
		$validated_transcripts{$unique_id}{'exon_coords'}{$db[5]} = $db[6];
		$validated_transcripts{$unique_id}{'avatar'}=$db[7];
	}
	return \%validated_transcripts;
}

########################################
#checks if transcript_1 is the same as transcript_2 (apart from UTR lengths). 


sub compare_transcripts{
	my ($transcript_1, $transcript_2 ) = @_;
	my %transcript_1 = %$transcript_1;
	my %transcript_2 = %$transcript_2;
	my $scaffold_match = 0;
	my $cds = 0;
	my $exon_starts = 0;
	my $exon_ends = 0;
	my $cds_match = 0;
	my $exon_match = 0;
	if ($transcript_1{'scaffold'} eq $transcript_2{'scaffold'} && $transcript_1{'strand'} eq $transcript_2{'strand'}){ $scaffold_match = 1; }
	#cdss have to match exactly
	foreach my $cds_start (keys %{$transcript_1{'cds_coords'}}){
		if (exists $transcript_2{'cds_coords'}{$cds_start}){
			if ($transcript_1{'cds_coords'}{$cds_start} == $transcript_2{'cds_coords'}{$cds_start}){
				$cds++;
			} 	
		}
	}
	if ($cds == scalar keys %{$transcript_1{'cds_coords'}}  && $cds == scalar keys %{$transcript_2{'cds_coords'}} ){
		$cds_match = 1;
	}
	my @transcript_1_exons = sort {$a <=> $b} keys %{$transcript_1{'exon_coords'}};
	my @transcript_2_exons = sort {$a <=> $b} keys %{$transcript_2{'exon_coords'}};	
	if (scalar @transcript_1_exons == scalar @transcript_2_exons){  
	#start boundaries of all but the first exons need to match.
		my $n = (scalar @transcript_1_exons) - 1;
		foreach my $i (1 .. $n){
			unless ($transcript_1_exons[$i] == $transcript_2_exons[$i]){
				last;
			}
			$exon_starts++;
		}
	#end boundaries of all but the last exons need to match	
		foreach my $i (0 .. ($n-1)){
			unless ($transcript_1{'exon_coords'}{$transcript_1_exons[$i]} == $transcript_2{'exon_coords'}{$transcript_2_exons[$i]}){
				last;
			}
			$exon_ends++;
		}
		if ($exon_starts == $n && $exon_ends == $n){ $exon_match = 1;  } 
	}
	if ($scaffold_match == 1 && $cds_match == 1 && $exon_match == 1){
		$transcript_1{'collapsed_id'} = $transcript_2;
	}
	return \%transcript_1;
}

########################################

sub reconcile_utrs{
	my ($collapsed_id, $dbh)= @_;
        my $sth_get_longest_utrs = $dbh->prepare('SELECT validated_transcripts.collapsed_id, MIN(validated_transcripts_exons.start_exon), MAX(validated_transcripts_exons.stop_exon) FROM validated_transcripts LEFT JOIN validated_transcripts_exons ON validated_transcripts.unique_id = validated_transcripts_exons.unique_id WHERE validated_transcripts.collapsed_id = ?');
	my $sth_get_current_utrs = $dbh->prepare('SELECT MIN(start_exon), MAX(stop_exon) FROM combined_exons WHERE collapsed_id = ?');
	my $sth_update_start_utr = $dbh->prepare('UPDATE combined_exons SET start_exon = ? WHERE collapsed_id =? AND start_exon = ?');
	my $sth_update_stop_utr = $dbh->prepare('UPDATE combined_exons SET stop_exon = ? WHERE collapsed_id = ? AND stop_exon = ?');	
	$sth_get_current_utrs->execute($collapsed_id);
	my ($current_start, $current_stop, $max_start, $max_stop);
	while (my @current_utrs_db = $sth_get_current_utrs->fetchrow_array){
		$current_start = $current_utrs_db[0];
		$current_stop = $current_utrs_db[1];
	}
	$sth_get_longest_utrs->execute($collapsed_id);
	while (my @longest_utrs_db = $sth_get_longest_utrs->fetchrow_array){
		$max_start = $longest_utrs_db[1];
		$max_stop = $longest_utrs_db[2];
	}	
	$sth_update_start_utr->execute($max_start,$collapsed_id,$current_start);
	$sth_update_stop_utr->execute($max_stop,$collapsed_id,$current_stop);	
}

#########################################

sub assign_transcripts_to_genes{ 
	my ($collapsed_transcripts, $dbh) = @_;
	my %orphan_transcripts;
	my $sth_get = $dbh->prepare('SELECT combined_ids.parent_gene FROM combined_ids LEFT JOIN combined_cds ON combined_ids.collapsed_id = combined_cds.collapsed_id WHERE combined_ids.scaffold = ? AND combined_ids.strand = ? AND ((combined_cds.start_cds <= ? AND combined_cds.stop_cds >= ?) OR (combined_cds.start_cds <= ? AND combined_cds.stop_cds >= ?)) AND combined_cds.frame = ?');
	my $sth_insert = $dbh->prepare('UPDATE combined_ids SET parent_gene = ? WHERE collapsed_id = ?');
	my $sth_name = $dbh->prepare('SELECT MAX(parent_gene) FROM combined_ids');
	TRANSCRIPT: foreach my $collapsed_id (keys %$collapsed_transcripts){
		next if (defined $collapsed_transcripts->{$collapsed_id}{'parent_gene'});
		my $scaffold =  $collapsed_transcripts->{$collapsed_id}{'scaffold'};
		my $strand =  $collapsed_transcripts->{$collapsed_id}{'strand'};
		foreach my $cds_start (keys %{$collapsed_transcripts->{$collapsed_id}{'cds_coords'}}){
			my $cds_end = $collapsed_transcripts->{$collapsed_id}{'cds_coords'}{$cds_start};
			my $rf = $collapsed_transcripts->{$collapsed_id}{'cds_frame'}{$cds_start};
			$sth_get->execute($scaffold,$strand,$cds_start,$cds_start,$cds_end,$cds_end,$rf);
			while (my @genes = $sth_get->fetchrow_array){
				if (defined $genes[0]){ 
					my $parent_gene = $genes[0];
					$sth_insert->execute($parent_gene, $collapsed_id);
					next TRANSCRIPT;
				 }
			}
		}
		my $parent_gene;
		$sth_name->execute();
		while (my @genes = $sth_name->fetchrow_array){
			if (defined $genes[0]){
				$parent_gene = $genes[0];	
				$parent_gene++;
			}
			else{ $parent_gene = 1; }
			$sth_insert->execute($parent_gene,$collapsed_id);
		}
	}
}



#########################################
#ensures that all students have 10 tokens
sub allocate_tokens{
	my ($sth_allocate_tokens, $users, $tokens, $date) = @_;
	my %users = %$users;
	my %tokens = %$tokens;
	my %school_tokens;
	foreach my $token (keys %tokens){
		if ($tokens{$token} >=10) { delete $tokens{$token};  }
	}
	foreach my $student (keys %users){
		my $school = $users{$student}{'school'};
		foreach my $token (keys %{$users{$student}{'all_tokens'}}){
			$school_tokens{$school}{$token} = ();
		}
	}
	#first try to only give the token if nobody else in the school has had it already
	foreach my $student (keys %users){
		my $reallocation = 0;
		my $i = 0;
		my $school = $users{$student}{'school'};
		while (scalar keys %{$users{$student}{'current_tokens'}} < 10){
			my @available_tokens = keys %tokens;
			if (scalar @available_tokens == 0){ die "Run out of available tokens!\n";}
			my $token = $available_tokens[$i];
			unless (exists $school_tokens{$school}{$token}){
                        	$sth_allocate_tokens->execute($token, $student, $date);
                                $school_tokens{$school}{$token}++;
                                $tokens{$token}++;		
				$users{$student}{'current_tokens'}{$token} = ();		
				$users{$student}{'all_tokens'}{$token} = (); 
                                if ($tokens{$token} >= 10){
                                	delete $tokens{$token};
                                }
			}	
			$i++;
                        if ($i >= scalar @available_tokens){
                        	$reallocation = 1;
                                last;
                        }		
		}

	#Then reallocate within the school if necessary
		if ($reallocation == 1){
			while (scalar keys %{$users{$student}{'current_tokens'}} < 10){
				my @available_tokens = keys %tokens;
				if (scalar @available_tokens == 0){ die "Run out of available tokens!\n";}
				my $token = $available_tokens[$i];
				unless (exists $users{$student}{'all_tokens'}{$token}){
					$sth_allocate_tokens->execute($token, $student, $date);
					$school_tokens{$school}{$token}++;
					$tokens{$token}++;      
					$users{$student}{'current_tokens'}{$token} = (); 
					$users{$student}{'all_tokens'}{$token} = (); 
				        if ($tokens{$token} >= 10){
                                        	delete $tokens{$token};
                                	}  
				}
				$i++;
			}
		}
	}
}

###########################################
sub allocate_tokens_v2{
	my ($sth_allocate_tokens, $users, $tokens, $date, $format) = @_;
        my %users = %$users;
        my %tokens = %$tokens;
	my @tokens;
	if ($format eq 'aggregate'){
		@tokens = sort { $tokens{'aggregate_score'}{$b} <=> $tokens{'aggregate_score'}{$a} } (keys %{$tokens{'aggregate_score'}});
	}
	elsif ($format eq 'iso'){
		@tokens = sort { $tokens{'iso_score'}{$b} <=> $tokens{'iso_score'}{$a} } (keys %{$tokens{'iso_score'}});	
	}
	print join("\n",@tokens);
	#print scalar(@tokens);
	foreach my $student (keys %users){
		while (scalar keys %{$users{$student}{'current_tokens'}} < 10){
			print $student, "\n";
			foreach my $i (0..scalar @tokens){
				my $token  = $tokens[$i];
				print $token, "\n";
				if (exists $users{$student}{'all_tokens'}{$token}){
					next;
				}
				$users{$student}{'current_tokens'}{$token} = ();
				$sth_allocate_tokens->execute($token, $student, $date);
				if (scalar keys %{$users{$student}{'current_tokens'}} == 10){
					last;
				}
			}
		}
	}
}


###########################################
sub apollo_dump{
	my ($organism, $apollo_pword, $type, $path, $date) = @_;
	my %options = ('timeout' => 10000);
	my $http = HTTP::Tiny->new(%options);
	my $server = 'http://wp-p2m-80.ebi.ac.uk:8080/IOService/write';
	my $username = 'irisadmin@local.host';
	my $content = "{'username': ".$username.", 'password': ".$apollo_pword.", 'format': 'text', 'organism' : ".$organism.", 'output' : 'text',";
	if ($type eq 'gff'){ $content .= "'type' : 'GFF3'}";}
	if ($type eq 'cds.fasta'){ $content .= "'type' : 'FASTA', 'seqType' : 'cds'}";}
	if ($type eq 'peptide.fasta'){ $content .= "'type' : 'FASTA', 'seqType' : 'peptide'}";}  
	print STDERR "Dumping $organism $type...";
	my $response = $http->request('POST',$server, {
        	headers => {'Content-type' => 'application/json'},
       		content => $content
	});
#	print Dumper \$response, "\n";
	die "Apollo dump failed" unless $response->{'success'};
	print STDERR "Success\n";
	open FH, '>', $path.'/'.$date.'/'.$organism.'.'.$type;
	print FH $response-> {'content'};
	close FH;
}

################################################
sub delete_feature{
	my ($organism, $feature, $apollo_pword) = @_;
	my $http = HTTP::Tiny->new;
        my $server = 'http://wp-p2m-80.ebi.ac.uk:8080/annotationEditor/deleteFeature';
        my $username = 'irisadmin@local.host';
        my $response = $http->request('POST',$server, {
                headers => {'Content-type' => 'application/json'},
                content => "{'username' : ".$username.", 'password' : ".$apollo_pword.",'features' : [{'uniquename' :".$feature." }], 'organism' : ".$organism."}"
        });
	print Dumper \$response;
	die "Deletion failed" unless $response->{'success'};
}

####################################################
sub delete_all_features{
	my ($organism, $apollo_pword) = @_;
	my %options = ('timeout' => 10000);
	my $http = HTTP::Tiny->new(%options);
	my $username = 'admin@local.host';
	my $server = 'http://muffin.ve3w6jjywh.us-east-1.elasticbeanstalk.com/organism/deleteOrganismFeatures';
	my $response = $http->request('POST',$server,{
		headers => {'Content-type' => 'application/json'},
		content => "{'username': ".$username.", 'password': ".$apollo_pword." , 'organism' : ".$organism."}"
	});
	print Dumper \$response;
	die "Failed!\n" unless $response->{success};
}

