#!/usr/bin/bash -l
set -e

MODULEPATH=/nfs/panda/ensemblgenomes/wormbase/modulefiles
module load apollo

ANNOTATIONS_DIR_PATH=$IRIS_HOME/GFF_dumps/t_trichiura/phase_2
DATA_DIR_PATH=$IRIS_HOME/iris/data

USAGE="You need to provide the following arguments:
-u - a file of user IDs to process (in the format avatar@apollo).
-m - the password to the mysql server.\n"

while getopts "u:" args
do
	case $args in

		u)
			USERS=$OPTARG
			;;

		\?)
			printf "$USAGE"
			exit
			;;
	esac
done
	
if [[ -z $USERS ]]
then
	printf "$USAGE"
	exit
fi
	
DATE=`date +%Y-%m-%d`

#dump and process GFFs
$IRIS_HOME/iris/bin/process_tokens.pl --user_list $USERS --annotations_path $ANNOTATIONS_DIR_PATH --apollo_pword $APOLLO_ADMIN_PASS --mysql_pword $MYSQL_PASS --data_path $DATA_DIR_PATH 

#write html files
$IRIS_HOME/iris/bin/write_html_files.pl --annotations_path $ANNOTATIONS_DIR_PATH --mysql_pword $MYSQL_PASS --data_path $DATA_DIR_PATH

#push html files to AWS
#aws s3 cp $ANNOTATIONS_DIR_PATH/$DATE/html/ s3://iris.testbucket/ --recursive --acl public-read

#back up the tokens database
mysqldump -h mysql-wormbase-pipelines -P 4331 -u wormadmin -p$MYSQL_PASS iris_tokens > $ANNOTATIONS_DIR_PATH/$DATE/iris_tokens.bak

#process annotations
$IRIS_HOME/iris/bin/process_annotations.pl --user_list $USERS --annotations_path $ANNOTATIONS_DIR_PATH --apollo_pword $APOLLO_ADMIN_PASS --mysql_pword $MYSQL_PASS --data_path $DATA_DIR_PATH

#back up the annotations database
mysqldump -h mysql-wormbase-pipelines -P 4331 -u wormadmin -p$MYSQL_PASS iris_genes > $ANNOTATIONS_DIR_PATH/$DATE/iris_genes.bak
