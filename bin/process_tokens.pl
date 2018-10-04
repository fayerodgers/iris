#!/usr/bin/env perl

use warnings;
use strict;
use Data::Dumper;
use DBI;
use DBD::mysql;
use POSIX qw(strftime);
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin";
use Apollo_fr;

my ($users, $annotations_path, $apollo_pword, $mysql_pword, $data_path);

my $usage = "You need to provide the following options:\n
	--user_list - a file of user IDs to process (in the format avatar\@apollo).\n
	--annotations_path - the path to the directory where GFFs and FASTAs should be dumped.\n
	--apollo_pword - the admin password to Apollo.\n
	--mysql_pword - the password to the mysql server.\n 
	--data_path - the path to the directory where data (evidence) files are saved.\n
";

GetOptions(
	'user_list=s' => \$users,
	'annotations_path=s' => \$annotations_path,
	'apollo_pword=s' => \$apollo_pword,
	'mysql_pword=s' => \$mysql_pword,
	'data_path=s' => \$data_path
) or die "$usage";

foreach my $option ($users, $annotations_path, $apollo_pword, $mysql_pword, $data_path){ 
	unless (defined $option){ print $usage; die; }
}

#connect to the database and prepare sth statements
my $dbh = connect_to_iris_database('iris_tokens', $mysql_pword);
my ($sth_allocate_tokens, $sth_reallocate_tokens, $sth_get_allocated_tokens, $sth_update_token_outcomes, $sth_update_transcript_outcomes, $sth_get_event_id)  = prepare_sql_statements($dbh, 'iris_tokens');

#make a new directory to dump the data into
my $date = strftime "%F", localtime;
unless (-d $annotations_path.'/'.$date){ system (mkdir $annotations_path.'/'.$date);}

#get users for processing
my %all_users;
open USERS, '<', $users or die "can't open list of users";
while(<USERS>){ 
        chomp;
        if (/((.+)_.+)\@apollo/){
                my $user = $1;
                my $school = $2;
                $all_users{$user} = $school;
        }
        else{ die "can't parse user file"; }
}

#dump GFFs
foreach my $user (keys %all_users){
	my $organism = join "",'trichuris_trichiura_', $user;
	unless (-f $annotations_path.'/'.$date.'/'.$organism.'.gff'){
		apollo_dump($organism,$apollo_pword,'gff',$annotations_path,$date);
		sleep(5);
	}
}

#parse GFFs
my (%transcripts, %tokens);
my $transcripts = \%transcripts;
my $tokens = \%tokens;
foreach my $user (keys %all_users){
	my $gff = join "",$annotations_path,'/',$date,'/trichuris_trichiura_',$user,'.gff';
	($tokens, $transcripts) = parse_gff($user, $gff, $tokens, $transcripts);
}
#print Dumper \$tokens;
#print Dumper \$transcripts;
%tokens = %$tokens;
%transcripts = %$transcripts;


#delete tokens that have been validated or rejected previously
#check that all returned tokens exist in allocated_tokens. Add them if not.
my %allocations;
$sth_get_allocated_tokens->execute();
while (my @tokens = $sth_get_allocated_tokens->fetchrow_array){
	if (defined $tokens[3]){
		if ($tokens[2] =~ /^validated/){
			$allocations{$tokens[0]}{'validated'}{$tokens[1]} = ();
		}
		if ($tokens[2] =~ /complex/){
			$allocations{$tokens[0]}{'validated'}{$tokens[1]} = ();
		}
		if ($tokens[2] =~ /manual_check/){
                	$allocations{$tokens[0]}{'validated'}{$tokens[1]} = ();
                }
	}
	else{$allocations{$tokens[0]}{'allocated'}{$tokens[1]} = ();}
}
#print Dumper \%allocations;
foreach my $user (keys %tokens){
	foreach my $unique_token_id (keys %{$tokens{$user}}){
		my $token_id = $tokens{$user}{$unique_token_id}{'name'};
		if (exists $allocations{$user}{'validated'}{$token_id}){
			delete $tokens{$user}{$unique_token_id}; next;
		}
		unless (exists $allocations{$user}{'allocated'}{$token_id}){
			$sth_allocate_tokens->execute($token_id,$user,$date);		
		}
	}
}

#dump CDS and peptide FASTAs for users with tokens to validate.
my @users= keys %tokens;
$transcripts = dump_FASTAs(\@users,\%transcripts,$apollo_pword,$annotations_path,$date);

#validate coverage, intron support and CDS.
my $introns_bed_file = $data_path.'/TTRE_all_introns.bed';
my $illumina_coverage_file = $data_path.'/coverage_blocks.bg';
my $isoseq_coverage_file = $data_path.'/isoseq_coverage_blocks.bg';
foreach my $user (keys %tokens){ 
	next unless (exists $transcripts{$user});
	my $peptide_fasta = join "", $annotations_path, '/', $date, '/trichuris_trichiura_',$user,'.peptide.fasta';
	my $t = validate_intron_boundaries($transcripts{$user},$introns_bed_file);
	$t = validate_coverage($t, $illumina_coverage_file, $isoseq_coverage_file);
	$t = validate_peptide($t, $peptide_fasta);
	$transcripts{$user} = $t;
}
#print Dumper \%transcripts;
#print Dumper \%tokens;
#map transcripts to tokens
foreach my $user (keys %tokens){
        foreach my $unique_token_id (keys %{$tokens{$user}}){
		foreach my $unique_transcript_id (keys %{$transcripts{$user}}){
			if ($tokens{$user}->{$unique_token_id}->{'scaffold'} eq $transcripts{$user}->{$unique_transcript_id}->{'scaffold'}){
				my $transcript_start = $transcripts{$user}{$unique_transcript_id}{'start'};
				my $transcript_end = $transcripts{$user}{$unique_transcript_id}{'end'};
				my $token_start = $tokens{$user}{$unique_token_id}{'start'};
				my $token_end = $tokens{$user}{$unique_token_id}{'end'};
				if ($transcript_start >= $token_start && $transcript_start <= $token_end){
					$tokens{$user}{$unique_token_id}{'transcripts'}{$unique_transcript_id}=();		
				}	
				elsif ($transcript_end >= $token_start && $transcript_end <= $token_end){
					 $tokens{$user}{$unique_token_id}{'transcripts'}{$unique_transcript_id}=();
				}
			}
		}
	}
}
#print Dumper \%tokens;

#update token outcomes
foreach my $user (keys %tokens){
	my $organism = join "",'trichuris_trichiura_', $user;
	foreach my $unique_token_id (keys %{$tokens{$user}}){
		my $token_name = $tokens{$user}{$unique_token_id}{'name'}; 	
		unless (exists $tokens{$user}{$unique_token_id}{'transcripts'}){
			$sth_update_token_outcomes->execute('empty',$date,$token_name,$user);
			print STDERR "Deleting Token $token_name for user $user - empty\n";
			delete_feature($organism,$unique_token_id,$apollo_pword);
			sleep (5);
			next;
		}
		if (exists $tokens{$user}{$unique_token_id}{'rejection'}){
			$sth_update_token_outcomes->execute($tokens{$user}{$unique_token_id}{'rejection'},$date,$token_name,$user);
		}
		else{
			my $valid = 0;
			my $event_id;
			foreach my $unique_transcript_id (keys %{$tokens{$user}{$unique_token_id}{'transcripts'}}){
				if (exists $transcripts{$user}{$unique_transcript_id}{'NE'}){
					next;
				}
				foreach my $test ('C', 'I', 'S', 'ST', 'IS'){
					if (exists $transcripts{$user}{$unique_transcript_id}{$test}){
						$transcripts{$user}{$unique_transcript_id}{'validation_summary'} .= $test.'1.';
					}
					else{ $transcripts{$user}{$unique_transcript_id}{'validation_summary'} .= $test.'0.';}
				}
				if ($transcripts{$user}{$unique_transcript_id}{'validation_summary'} =~ /0/){
					$valid++;
					$sth_update_token_outcomes->execute('not_validated',$date,$token_name,$user);
					$sth_get_event_id->execute($token_name,$user,$date);
					my $transcript_name = $transcripts{$user}{$unique_transcript_id}{'name'};
					my $test_outcomes = $transcripts{$user}{$unique_transcript_id}{'validation_summary'};
					while (my @event_id = $sth_get_event_id->fetchrow_array){
						$event_id = $event_id[0];
					}
					$sth_update_transcript_outcomes->execute($event_id,$unique_transcript_id,$transcript_name,$test_outcomes);
				}
			}
			if ($valid>0){
				$sth_reallocate_tokens->execute($token_name,$user,$date,$event_id);
				print STDERR "Deleting Token $token_name for user $user - not validated\n";
				delete_feature($organism,$unique_token_id,$apollo_pword);
			} 
			if ($valid == 0){
				$sth_update_token_outcomes->execute('validated',$date,$token_name,$user);
			}
		}
	}
}

#reallocate tokens
my $all_users= retrieve_all_users_from_db($dbh);
my $all_tokens = retrieve_token_data($dbh);
allocate_tokens($sth_allocate_tokens, $all_users, $all_tokens, $date);

