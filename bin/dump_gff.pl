#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin";
use Apollo_fr;
use POSIX qw(strftime);
use Getopt::Long;

my ($organism,$apollo_pword,$path) = @_;

my $usage = "Required options:\n
	--organism\n 
	--apollo_pword\n
	--path (the directory where the GFF should be dumped)\n
";

GetOptions(
	'organism=s' => \$organism,
	'apollo_pword=s' => \$apollo_pword,
	'path=s' => \$path
) or die "$usage";

foreach my $option ($organism, $apollo_pword, $path){
	unless (defined $option) { print $usage; die; }
}

my $date = strftime "%F", localtime;
unless (-d $path.'/'.$date){ system (mkdir $path.'/'.$date);}
apollo_dump($organism,$apollo_pword,'gff',$path,$date);
