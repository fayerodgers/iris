from __future__ import division
import sys
sys.path.append('/nfs/production/panda/ensemblgenomes/wormbase/projects/IRIS/iris/isoseq_scripts')
import re
import pprint
import mysql.connector
import config
import json
import isoseq

cnx=mysql.connector.connect(**config.config_iris)
cursor=cnx.cursor()

#get token scores for each feature
tokens={}
transdecoder_scores=[]
iris_scores=[]

get_scores=("SELECT token_id,isoseq_score,transdecoder_score,iris_score,illumina_score,manual_score,score FROM tokens")
coverage=[]
cursor.execute(get_scores)
for (token_id,isoseq_score,transdecoder_score,iris_score,illumina_score,manual_score,score) in cursor:
	tokens[token_id] = {}
	x=float(isoseq_score)-float(transdecoder_score)
	if x <= 0:
		tokens[token_id]['transdecoder'] = 0
	else:
		tokens[token_id]['transdecoder']=x/float(isoseq_score)	
	y=float(isoseq_score)-float(iris_score)
	if y <= 0:
		tokens[token_id]['iris'] = 0
	else:
		tokens[token_id]['iris']=y/float(isoseq_score)
	
	tokens[token_id]['illumina']=illumina_score
	tokens[token_id]['manual']=manual_score
	tokens[token_id]['isoseq_coverage']=float(score)
	coverage.append(score)

coverage_scale_factor =float(max(coverage))

update_scores=("UPDATE tokens SET aggregate_score=%s WHERE token_id = %s")
for token in tokens.keys():
	if tokens[token]['manual']>0:
		aggregate = tokens[token]['manual']
	else:
		tokens[token]['isoseq_coverage']=tokens[token]['isoseq_coverage']/coverage_scale_factor
		aggregate=((2*tokens[token]['transdecoder']) + (2*tokens[token]['iris']) + (tokens[token]['isoseq_coverage']))/5
	data=(aggregate,token)
	cursor.execute(update_scores,data)

cnx.commit()
cursor.close()
cnx.close()

	


