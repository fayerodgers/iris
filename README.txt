Scripts and data files for processing IRIS annotations from Apollo.

Summary of scripts found in the bin directory (run any script with no options to get its usage):

process_tokens.pl : 
	-dumps GFFs of all users
	-runs the following validation checks on all transcripts:
		1. Intron boundaries are supported by Illumina data
		2. Every base has expression evidence (Illumina or IsoSeq)
		3. Has a start codon
		4. Has a stop codon
		5. No internal stop codons
	-Maps transcripts to returned tokens
	-For each returned token, determines whether the token is:
		1. "validated" - all transcripts that overlap the token pass all validation checks.
		2. "not_validated" - at least one transcript overlapping the token has failed a validation check. Tokens that are not validated are deleted from the account's scratch pad in Apollo, to be re-promoted by the user when the problem is fixed.
		3. "empty" -  if no transcripts overlap the token it is presumed to have been returned in error. Empty tokens are deleted from the account's scratch pad.
		4. "complex" - if a user has used the pre-canned comment "complex" to say that the genes on the token are too complex for them to curate.
		5. "manual_check" - if a user has used the pre-canned comment "manual check" to indicate that the token should be checked by a curator. Intended use is for tokens that contain transcripts that have failed the validation checks but the users still thinks their transcript model is correct.
	-Each token's outcome is recorded in the iris_tokens database (relevant table: allocated_tokens). For not_validated transcripts, the test outcomes of the failed transcript(s) are also recorded (relevant table: nonvalidated_transcripts)
	-Each user is then allocated new tokens (to replace those that are validated, complex or need manual checking) to a total of ten tokens. Tokens that were empty or not validated are allocated to the same user again.

write_html_files.pl :
	-writes one HTML file per user summarising their current and past token allocations (reading from iris_tokens). The HTML template is in the data directory.

process_annotations.pl : 
	-validates all transcripts of all users, and puts valid transcripts into the iris_genes database
	-Collapses redundant transcripts and reconciles UTRs (if two or more transcripts have the same CDS and same intron/exon structure, they are collapsed into one combined transcript and its UTRs extended to match the max length found in any of the redundant transcripts)
	-Assigns transcripts to parent genes (transcripts are considered to be from the same gene if they have overlapping CDS in the same readinf frame).

iris_master.sh
	-Strings the above together (with a few other things, eg backing up the databases).

Apollo_fr.pm
	-Defines subroutines used in the above.
