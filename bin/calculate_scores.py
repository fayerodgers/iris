import sys
sys.path.append('../isoseq_scripts')
import re
import pprint
import mysql.connector
import config
import json
import isoseq
import argparse

parser=argparse.ArgumentParser(description='calculate various feature scores for tokens')
parser.add_argument('--transdecoder',action='store',help='transdecoder GFF')
parser.add_argument('--iris', action='store',help='iris GFF')
parser.add_argument('--illumina',action='store',help='Illumina something')
parser.add_argument('--isoseq',action='store_true',help='use this option to update the IsoSeq scores')

args=parser.parse_args()
features_to_score=[]

###
def check_overlap(feature_1,feature_2):
        if feature_1['scaffold'] != feature_2['scaffold']:
                return None
        if feature_1['start']>feature_2['end']: 
                return None
        if feature_1['end']<feature_2['start']:
                return None
        return 1
###


#open GFFs to be scored

#get tokens from the iris database
tokens={}
tokens_cnx=mysql.connector.connect(**config.config_iris)
tokens_cursor=tokens_cnx.cursor()

select_tokens=("SELECT token_id,start_coord,end_coord,scaffold FROM tokens")
tokens_cursor.execute(select_tokens)
for (token_id,start_coord,end_coord,scaffold) in tokens_cursor:
        tokens[token_id]={}
        tokens[token_id]['start']=start_coord
        tokens[token_id]['end']=end_coord
        tokens[token_id]['scaffold']=scaffold

features_to_score={}

if args.transdecoder:
	transdecoder=open(args.transdecoder,"r")
	(transdecoder_genes,transdecoder_transcripts)=isoseq.parse_gff(transdecoder)   
	print(json.dumps(transdecoder_genes,indent=4))
	#only keep transdecoder genes if they are classed as complete
	transdecoder=dict(transdecoder_genes)
	for gene in transdecoder_genes:
		if transdecoder_genes[gene]['type'] != 'complete':
			transdecoder.pop(gene)
	transdecoder=isoseq.feature_level_clustering(transdecoder)
#	print(json.dumps(transdecoder_blocks,indent=4))
	features_to_score['transdecoder_score']=transdecoder	

if args.iris:
        iris=open(args.iris,"r")
        (iris_genes,iris_transcripts)=isoseq.parse_gff(iris)
	features_to_score['iris_score']=iris_genes

if args.isoseq is True:
        reads=isoseq.retrieve_reads('all')
        isoseq_blocks=isoseq.feature_level_clustering(reads)
#       print(json.dumps(isoseq_blocks,indent=4))
	features_to_score['isoseq_score']=isoseq_blocks


for token in tokens:
	for key,value in features_to_score.iteritems():
	 	tokens[token][key]=0
		for i in value:
			if check_overlap(tokens[token],value[i]):
				tokens[token][key]+=1
		update_score=("UPDATE tokens SET "+key+"=%s WHERE token_id=%s")
		data=(tokens[token][key],token)
		tokens_cursor.execute(update_score,data)

tokens_cnx.commit()
tokens_cursor.close()
tokens_cnx.close()

print(json.dumps(tokens,indent=4))






