#!/bin/bash

if [ ! -z "$BROWSER" ]; then 
	MYBROWSER=${BROWSER//[%s\ \'&]/}
else 
	MYBROWSER=firefox
fi

echo "Going to start $MYBROWSER now. don't be alarmed"
sleep 2



# 1 - get api key

SESSION_FILE=$HOME/.mpc/last.fm
SERVICE=http://ws.audioscrobbler.com/2.0/
APIKEY=1dfdc3a278e6bac5c76442532fcd6a05 # mpc-last
SECRET=a70bafc9e39612700a2c1b61b5e0ab61
#LASTFM_USER=`awk -F: '{print $1 }' $SESSION_FILE ` 
#LASTFM_SK=`awk -F: '{print $2 }' $SESSION_FILE ` 


# 2 - Fetch an unathorized request token for an API account. 
# 		Web applications do not need to use this service. 
# 		expires in 60 min
#MS=$(echo -n ${APIKEY}auth.gettoken${SECRET}|md5sum|cut -d' ' -f1)
#MS=a79d11d25b658decd1f0e49f841e0359
RT_RESPONSE=`curl -s "$SERVICE?method=auth.gettoken&api_key=$APIKEY"`
RT=`echo $RT_RESPONSE | sed 's/.*<token>\(.*\)<\/token>.*/\1/'  `




# 3 - get user authorization
#
if [ `echo $RT | grep -qE "[a-z0-9]{32}"; echo $? ` -eq 0 ];then

	if [ -x "$MYBROWSER" ] && [ -n "$DISPLAY" ]; then
		$MYBROWSER "http://www.last.fm/api/auth/?api_key=$APIKEY&token=$RT"
	else
		echo look here: "http://www.last.fm/api/auth/?api_key=$APIKEY&token=$RT"
	fi

	while [ "$CONTINUE" != "yes" ];do 
		read -p "done in $MYBROWSER?: " CONTINUE
	done
	if [ "$CONTINUE" != "yes" ];then exit; fi
else 
	echo $RT_RESPONSE | sed 's/.*<error.*code="\(.*\)"[^>]*>\(.*\)<[^>][^>]*>.*/\1 \2/' 
	exit 1
fi


# 4 - get web server session (infinite life time)
#
MS="api_key${APIKEY}"
MS="${MS}methodauth.getsession"
MS="${MS}token${RT}"
MS="${MS}${SECRET}"
MS=`echo -n $MS |md5sum|cut -d' ' -f1`


WSS=`curl -s "$SERVICE?method=auth.getsession&api_key=${APIKEY}&token=${RT}&api_sig=${MS}"`; 

OUT=`echo $WSS | sed 's/.*<name>\(.*\)<\/name>.*/\1/' `
OUT=${OUT}:`echo $WSS|sed 's/.*<key>\(.*\)<\/key>.*/\1/'` 

if [ -e  $SESSION_FILE ];
then
	read -p "going to write over $SESSION_FILE if you say yes: " CONTINUE
	if [ "$CONTINUE" == "yes" ];
	then
		mkdir -p `dirname $SESSION_FILE` 2>/dev/null
		echo $OUT > $SESSION_FILE
		echo "sessionkey $OUT saved in $SESSION_FILE"
	else 
		echo ok. put it whereever: 
		echo $OUT
	fi

fi




# 5 - make authenticated calls
#
#RT=`get new`
#MS=$(echo -n ${APIKEY}apiMethod${SECRET}) # sort POST? parameters alphametically
##curl "$SERVICE?method=apiMethod?api_key=$AK?sk=$WSS?api_sig=$MS"
