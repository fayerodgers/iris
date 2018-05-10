#!/bin/bash
set -e

USAGE="You need to provide the following arguments:
-u - a file of user IDs to process (in the format avatar@apollo).
-d - the path to the directory where GFFs, FASTAs, HTML files and database back-ups should be written.
-a - the admin password to Apollo.
-m - the password to the mysql server.\n"

while getopts "u:d:a:m:" args
do
	case $args in

		u)
			USERS=$OPTARG
			;;
		
		d)
			ANNOTATIONS_DIR_PATH=$OPTARG
			;;
	
		a)
			APOLLO_PWORD=$OPTARG
			;;

		m)
			MYSQL_PWORD=$OPTARG
			;;

		\?)
			printf "$USAGE"
			exit
			;;
	esac
done
	
if [[ -z $USERS || -z $ANNOTATIONS_DIR_PATH || -z $APOLLO_PWORD || -z $MYSQL_PWORD ]]
then
	printf "$USAGE"
	exit
fi
	
DATE=`date +%Y-%m-%d`

#dump and process GFFs
./bin/process_tokens.pl --user_list $USERS --annotations_path $ANNOTATIONS_DIR_PATH --apollo_pword $APOLLO_PWORD --mysql_pword $MYSQL_PWORD 

#write html files
./bin/write_html_files.pl --annotations_path $ANNOTATIONS_DIR_PATH --mysql_pword $MYSQL_PWORD

#push html files to AWS
aws s3 cp $ANNOTATIONS_DIR_PATH/$DATE/html/ s3://iris.testbucket/ --recursive --acl public-read

#back up the tokens database
mysqldump -h mysql-wormbase-pipelines -P 4331 -u wormadmin -p$MYSQL_PWORD iris_tokens > $ANNOTATIONS_DIR_PATH/$DATE/iris_tokens.bak

#process annotations
./bin/process_annotations.pl --user_list $USERS --annotations_path $ANNOTATIONS_DIR_PATH --apollo_pword $APOLLO_PWORD --mysql_pword $MYSQL_PWORD

#back up the annotations database
mysqldump -h mysql-wormbase-pipelines -P 4331 -u wormadmin -p$MYSQL_PWORD iris_genes > $ANNOTATIONS_DIR_PATH/$DATE/iris_genes.bak
