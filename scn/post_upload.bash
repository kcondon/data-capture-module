#!/usr/bin/env bash

# post upload scanning (checksums and data movement)

echo "post_upload starting at " `date` 

LOCKFILE=/var/run/post_upload.pid

if [ ! -z "$DVAPIKEY" ]; then
	. $HOME/.bashrc
fi

#TODO - make configurable
DEPOSIT=/deposit
HOLD=/hold

SRC=/usr/local/dcm/

# user to own uploaded datasets; change to production user after testing
#TODO - make configurable
DSETUSER=sbgdb

if [ -e $LOCKFILE ]; then
	echo "post_upload scan still in progress at " `date` " , aborting"
	exit
fi
echo $$ > $LOCKFILE
trap "rm -f '$LOCKFILE'" EXIT

# scan for indicators
for indicator_file in `find $DEPOSIT -name files.sha`
do
	ddir=`dirname $indicator_file`
	ulid=`basename $ddir`
	echo $indicator_file " : " $ddir " : " $ulid

	# verify checksums prior to moving dataset
	cd ${DEPOSIT}/${ulid}/${ulid} 
	nl=`wc -l files.sha | awk '{print $1}'`
	shasum -s -c files.sha 
	err=$?
	if (( ( $err != 0 ) || ( $nl == 0 ) )); then
		# handle checksum failure
		mv files.sha files-`date '+%Y%m%d-%H:%M'`.sha # rename previous indicator file
		echo "checksum failure"
		msg=`cat $DEPOSIT/processed/${ulid}.json | jq ' . + {status:"validation failed"}'`
		echo "debug(msg): $msg"
		echo "$msg" > /tmp/${ulid}.json
		#sent to dv endpoint (only if API key set; log to stdout otherwise)
		#r=`curl -k -X POST -H "X-Dataverse-key: ${DVAPIKEY}" -H 'Content-Type: application/json' -H 'Accept: application/json' -d@/tmp/${ulid}.json https://$DVHOSTINT/api/datasets/dataCaptureModule/checksumValidation`
		#echo "debug(checksum failed curl):"
		#echo $r
		#TODO - cleanup /tmp once done testing
	else
		# handle checksum success
		echo "checksums verified"

		#move to HOLD location
		if [ ! -d ${HOLD}/${ulid} ]; then
			#change to subdirectory to match batch-import code changes
			mkdir -p ${HOLD}/${ulid}
			cp -a ${DEPOSIT}/${ulid}/${ulid} ${HOLD}/${ulid}/
			err=$?
			if (( $err != 0 )) ; then
				echo "dcm: file move $ulid" 
				break
			fi
			rm -rf ${DEPOSIT}/${ulid}/${ulid}
			#chown -R $DSETUSER:$DSETUSER ${HOLD}/${ulid}
			echo "data moved"
			# send space used to dv
			sz=`du -sb ${HOLD}/${ulid}` #FIXME - problems with $sz in message
			#msg=`cat $DEPOSIT/processed/${ulid}.json | jq ' . + {status:"validation passed",size_bytes:$sz}'`
			#echo "debug(msg): $msg"
			# send to dv endpoint 
			echo "$msg" > /tmp/${ulid}.json
			echo "dataset $ulid : space $sz : subdirectory ${ulid}"
			#sent to dv endpoint (only if API key set; log to stdout otherwise)
			#r=`curl -k -X POST -H "X-Dataverse-key: ${DVAPIKEY}" -H 'Content-Type: application/json' -H 'Accept: application/json' -d@/tmp/${ulid}.json https://$DVHOSTINT/api/datasets/dataCaptureModule/checksumValidation`
			#echo "debug(validation passed curl):"
			#echo $r
			#TODO - cleanup /tmp once done testing
		else
			echo "handle error - duplicate upload id $ulid"
			echo "problem moving data; bailing out"
			#TODO - dv isn't listening for this error condition
			break #FIXME - this breaks out of the loop; aborting the scan (instead of skipping this dataset)
		fi
		
		mv $DEPOSIT/processed/${ulid}.json $HOLD/stage/
		#de-activate key (still in id_dsa.pub if we need it)
		rm ${DEPOSIT}/${ulid}/.ssh/authorized_keys
	fi
	
done

