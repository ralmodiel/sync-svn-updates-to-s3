################################################################################
# Description:  
#      Requires shell commands svn and ruby-based s3cp (https://github.com/aboisvert/s3cp)
#      Invokes an svn update command and uses the result to update or delete the files in a S3 bucket
#      Allows update of http headers specific to the file type 
#      Uploads a gzip version for the html, js and css files
#      Creates an invalidation list for CloudFront deployment
# Usage:
#      Update the variables within the script or set(export) prior to calling this
#      ./svnco2s3.sh <svnrepopath> <svnworkspace>
#
# Author:  Roque Almodiel Jr.   roque.almodiel(at)gmail.com
# Date Created: 20130226
################################################################################

export SCRIPT_HOME=
export SVN_WORKSPACE=$2
export INVALIDATION_LIST=${SCRIPT_HOME}/invalidation_files/invalidation`date +"%Y%m%d%k%M%S"`.txt

##export AWS_CLOUDFRONT_DISTID=
#export AWS_ACCESS_KEY_ID=
#export AWS_SECRET_ACCESS_KEY=
#export S3_BUCKET=

export HTML_HEADER="--header \"Cache-Control: max-age=604800,must-revalidate\" --header \"Content-Type: text/html\""
export CSS_HEADER="--header \"Cache-Control: max-age=604800,must-revalidate\" --header \"Content-Type: text/css\""
export JS_HEADER="--header \"Cache-Control: max-age=604800,must-revalidate\" --header \"Content-Type: application/javascript\""
export PNG_HEADER="--header \"Cache-Control: max-age=2592000,must-revalidate\" --header \"Content-Type: image/png\""
export GIF_HEADER="--header \"Cache-Control: max-age=2592000,must-revalidate\" --header \"Content-Type: image/gif\""
export JPG_HEADER="--header \"Cache-Control: max-age=2592000,must-revalidate\" --header \"Content-Type: image/jpeg\""
export HTMLGZ_HEADER="--header \"Cache-Control: max-age=604800,must-revalidate\" --header \"Content-Type: text/html\" --header \"Content-Encoding: gzip\""
export CSSGZ_HEADER="--header \"Cache-Control: max-age=604800,must-revalidate\" --header \"Content-Type: text/css\" --header \"Content-Encoding: gzip\""
export JSGZ_HEADER="--header \"Cache-Control: max-age=604800,must-revalidate\" --header \"Content-Type: application/javascript\" --header \"Content-Encoding: gzip\""


mkdir $2 2>/dev/null
cd $2
svn co $1 . > $SCRIPT_HOME/svnupdate.log

cd $SCRIPT_HOME
rm -f $INVALIDATION_LIST 2>/dev/null
touch $INVALIDATION_LIST
cat $SCRIPT_HOME/svnupdate.log| while read LINE
do
    echo
    echo $LINE
    if [ "${LINE:0:7}" = "Updated" -o "${LINE:3:8}" = "revision" ]; then
        exit
    else
        #echo $LINE
        TYPE=`echo $LINE|awk '{print $1}'`
        FILE=`echo $LINE|awk '{print $2}'`

        if [ -d ${SVN_WORKSPACE}/${FILE} ]; then
            #file is a directory
            continue
        fi
        echo $FILE >> $INVALIDATION_LIST

        echo \>\>\> $FILE : $TYPE
        FILEEXT=`echo $FILE|awk -F . '{print $NF}'`
        HEADERVAR=`echo ${FILEEXT^^}_HEADER` 2>/dev/null
        #echo $HEADERVAR
        HTTPHEADER=${!HEADERVAR} 2>/dev/null
        HEADERVAR=`echo ${FILEEXT^^}GZ_HEADER` 2>/dev/null
        HTTPGZHEADER=${!HEADERVAR} 2>/dev/null
        #echo $HTTPHEADER
        #echo $HTTPGZHEADER

        if [ "$TYPE" == "A" -o "$TYPE" == "U" ]; then
            echo Copying $FILE to S3 bucket
            if [ "$HTTPHEADER" = "" ]; then
                 echo warning: no http header assigned for file extension $FILEEXT
                 s3cp ${SVN_WORKSPACE}/${FILE} s3://${S3_BUCKET}/${FILE}
            else
                 echo using --header "$HTTPHEADER"
                 CPCMD="s3cp ${SVN_WORKSPACE}/${FILE} s3://${S3_BUCKET}/${FILE} $HTTPHEADER"
                 eval $CPCMD
            fi
#            if [ "$TYPE" == "U" ]; then
#                cloudfront_cmd.rb \
#                    --distribution-id $AWS_CLOUDFRONT_DISTID \
#                    --access-key $AWS_ACCESS_KEY_ID \
#                    --secret-access-key $AWS_SECRET_ACCESS_KEY \
#                    invalidate_objects "${FILE}"
#            fi

            if [ $FILEEXT == "html" -o $FILEEXT == "css" -o $FILEEXT == "js" ]; then
                echo Copying compressed version for $FILE to S3 bucket
                cat ${SVN_WORKSPACE}/$FILE | gzip > ${SVN_WORKSPACE}/${FILE}.gz
                if [ "$HTTPGZHEADER" = "" ]; then
                    echo warning: no http header assigned for file extension ${FILEEXT}.gz
                    s3cp ${SVN_WORKSPACE}/${FILE}.gz s3://${S3_BUCKET}/${FILE}.gz
                else
                    CPCMD="s3cp ${SVN_WORKSPACE}/${FILE}.gz s3://${S3_BUCKET}/${FILE}.gz $HTTPGZHEADER"
                    eval $CPCMD
                fi
                echo ${FILE}.gz >> $INVALIDATION_LIST
#                if [ "$TYPE" == "U" ]; then
#                    cloudfront_cmd.rb \
#                      --distribution-id $AWS_CLOUDFRONT_DISTID \
#                      --access-key $AWS_ACCESS_KEY_ID \
#                      --secret-access-key $AWS_SECRET_ACCESS_KEY \
#                      invalidate_objects "${FILE}.gz"
#                fi
            fi
        elif [ "$TYPE" == "D" ]; then
            echo Deleting $FILE from S3 bucket
            s3rm s3://${S3_BUCKET}/${FILE}
            if [ $FILEEXT == "html" -o $FILEEXT == "css" -o $FILEEXT == "js" ]; then
                s3rm s3://${S3_BUCKET}/${FILE}.gz
            fi
        fi 
    fi
done
if [ -f $INVALIDATION_LIST ]; then
    echo CloudFront invalidation list created: $INVALIDATION_LIST
else 
    rm $INVALIDATION_LIST
fi
echo Done.
