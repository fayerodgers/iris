#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use DBI;
use DBD::mysql;
use HTML::Template;
use POSIX qw(strftime);
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin";
use Apollo_fr;

my ($annotations_path, $mysql_pword, $data_path);

my $usage = "You need to provide the following options:\n
	--annotations_path - the path to the directory where HTML files should be written.\n
	--mysql_pword - the password to the mysql server.\n 
	--data_path - the path to the directory where the HTML template file is saved.\n
";

GetOptions(
	'annotations_path=s' => \$annotations_path,
	'mysql_pword=s' => \$mysql_pword,
	'data_path=s' => \$data_path
) or die "$usage";

foreach my $option ($annotations_path, $mysql_pword){ 
	unless (defined $option){ print $usage; die; }
}

my (%current_tokens, %past_tokens, %tests, %events);
my $date = strftime "%F", localtime;
my $dbh = connect_to_iris_database('iris_tokens',$mysql_pword);
unless (-d $annotations_path.'/'.$date.'/html'){ system (mkdir $annotations_path.'/'.$date.'/html');}

my $sth_get_token_info=$dbh->prepare('SELECT students.avatar,allocated_tokens.event_id, allocated_tokens.token_id, allocated_tokens.date_returned, allocated_tokens.outcome, allocated_tokens.previous_event_id,tokens.scaffold, tokens.start_coord, tokens.end_coord FROM students LEFT OUTER JOIN allocated_tokens ON students.avatar=allocated_tokens.avatar LEFT OUTER JOIN tokens ON allocated_tokens.token_id=tokens.token_id');
my $sth_get_transcript_history=$dbh->prepare('SELECT transcript_name, test_outcomes FROM nonvalidated_transcripts WHERE event_id = ?');
my $decode_test_results=$dbh->prepare('SELECT symbol, meaning FROM tests');


&decode_tests;
&sth_get_token_info;
&write_html;

#print Dumper (\%past_tokens);
#print Dumper (\%current_tokens);
#print Dumper (\%tests);


sub decode_tests{
        $decode_test_results->execute;
        while (my @tests = $decode_test_results->fetchrow_array){
                $tests{$tests[0]} = $tests[1];
        }
}

sub sth_get_token_info{
	$sth_get_token_info->execute;
	while (my @allocations = $sth_get_token_info->fetchrow_array){
		my $user = $allocations[0];
		my $event_id = $allocations[1];
		my $token_id = $allocations[2];
		my $date_returned = $allocations[3];
		my $outcome = $allocations[4];
		my $previous_event_id = $allocations[5];
		my $scaffold = $allocations[6];
		my $start_coord= $allocations[7];
		my $end_coord = $allocations[8];
		my $hyperlink = 'http://apollo.wormbase.org/annotator/LoadLink?organism=trichuris_trichiura_'.$user.'&loc='.$scaffold.':'.$start_coord.'..'.$end_coord;
		if (defined $date_returned){
			my %table_2;
			$events{$event_id}=$outcome;
			if ($outcome eq 'validated' || $outcome eq 'complex'){
				$table_2{'TOKEN'} = $token_id;
				$table_2{'APOLLO_LINK'} = $hyperlink;
				$table_2{'DATE'} = $date_returned;
				$table_2{'OUTCOME'} = $outcome;
				push @{$past_tokens{$user}}, \%table_2;
			}
		}
		else{
			my %table_1;
			$table_1{'TOKEN'} = $token_id;
			$table_1{'APOLLO_LINK'} = $hyperlink;
			if (defined $previous_event_id){
				$table_1{'STATUS'} = 'Double check';
				my $previous_outcome = $events{$previous_event_id};
				if ($previous_outcome eq 'empty'){
					$table_1{'DETAILS'} = 'Token was returned with no annotations';						
				}
				else{
					$sth_get_transcript_history->execute($previous_event_id);	
					while (my @histories = $sth_get_transcript_history->fetchrow_array){
						my $transcript_name = $histories[0];
						my @transcript_results = split /\./, $histories[1];
						my %decoded_transcript_results;
						foreach my $transcript_result (@transcript_results){
							if (exists $tests{$transcript_result}){
								$decoded_transcript_results{$tests{$transcript_result}} = ();
                                                       	}
                                               	}
						my @decoded_transcript_results=keys(%decoded_transcript_results);
						$table_1{'DETAILS'} .= 'Transcript '.$transcript_name.' has '.join(' and ', @decoded_transcript_results).'. ';
					}
				}
			}
			else{ $table_1{'STATUS'} = 'Not yet completed'; }
			push @{$current_tokens{$user}}, \%table_1;
		}
	}

}


sub write_html{
	foreach my $avatar (keys %current_tokens){
		open FH, '>', $annotations_path.'/'.$date.'/html/'.$avatar.'.html';
		my $template = HTML::Template->new(filename => $data_path.'/student_page_template.html');
		$template->param(
			CURRENT_TOKENS_ROWS => \@{$current_tokens{$avatar}},
			PAST_TOKENS_ROWS => \@{$past_tokens{$avatar}},
			AVATAR => $avatar
		);
		print FH $template->output;
	}
}


