#!/bin/bash

. ./eb.production.conf

export AWS_ACCESS_KEY_ID=$AccessKeyId
export AWS_SECRET_ACCESS_KEY=$SecretAccessKey
export AWS_DEFAULT_REGION=$Region

if ! command -v jq &> /dev/null
then
  # mkdir .tmp
  # cd .tmp
  # git clone https://github.com/stedolan/jq.git
  # cd jq
  # autoreconf -i
  # ./configure --disable-maintainer-mode
  # make
  # sudo make install
  sudo apt-get install jq -y
fi

if ! command -v semver &> /dev/null
then
  npm install -g semver -y
fi

# read -p "[deploy.sh] Choose version upgrade (major/minor/patch/same): " release_type
# if [[ "${release_type}" != "same" ]]; then
#   npm version $release_type --no-git-tag-version
#   NEW_VERSION=`node -p "require('./package.json').version"`;
#   sed -i "s/\"version\": \".*\"/\"version\": \"$NEW_VERSION\"/" package.production.json
#   sed -i "s/\"version\": \".*\"/\"version\": \"$NEW_VERSION\"/" package.serverless.json
# fi

# read -p "[deploy.sh] Do you want to commit current changes? (y/n): "  confirm
# dev_commit_message=""
# if [ "$confirm" = "y" ] ; then
#   read -p "[deploy.sh] Commit message: "  dev_commit_message
#   git add .
#   git commit -m "$dev_commit_message"
#   git push
# fi

rand=$( shuf -i 1-100000 -n 1 )

# read -p "[deploy.sh] Build files? (y/n): "  confirm
# dev_commit_message=""
# if [ "$confirm" = "y" ] ; then
#   npm run build
# fi

# cd build
# cp .env .env.backup
cd build

cp ../config.production.php ./config.php

zip -r "app-$rand.zip" .

environments=$( aws elasticbeanstalk describe-environments --application-name $AppName --environment-name $EnvName --region $Region )
currentversionlabel=$( jq -r '.Environments[] | .VersionLabel' <<< $environments )
IFS=', ' read -r -a array <<< "$currentversionlabel"
currentversion="${array[1]}"
echo "[deploy.sh] Current Version: $currentversion"
currentupload="${array[3]}"
echo "[deploy.sh] Current Upload: $currentupload"

newversion=$( jq -r .version ../package.json )
echo "[deploy.sh] New Version: $newversion"

if [ "$currentversion" != "$newversion" ] ; then
  newupload="01"
else
  newupload=$( expr $currentupload + 0 )
  newupload=$(( $newupload + 1 ))
  uploadlength=$( expr length $newupload )
  if (( $uploadlength == 1 )) ; then
    newupload="0$newupload"
  else
    newupload="$newupload"
  fi
fi

echo "[deploy.sh] New Upload: $newupload"

versionlabel="$VersionLabelPrefix $newversion - $newupload"
echo "[deploy.sh] Current Version Label: $currentversionlabel"
echo "[deploy.sh] New Version Label: $versionlabel"

existing_version_info=$( aws elasticbeanstalk describe-application-versions --application-name $AppName --version-labels "$versionlabel" --region $Region )
existing_version=$( jq -r '.ApplicationVersions[0]' <<< $existing_version_info )
if [ "$existing_version" != "null" ]; then
  read -p "[deploy.sh] Version $versionlabel already exists, it will have to be removed to proceed? (y/n): "  confirm
  if [ "$confirm" = "y" ] ; then
    aws elasticbeanstalk delete-application-version --application-name $AppName --version-label "$versionlabel" --region $Region
    echo "[deploy.sh] Successfully removed version $versionlabel."
  else
    echo "[deploy.sh] Deployment Aborted."
    exit 0
  fi
fi

read -p "[deploy.sh] Continue with deployment? (y/n): "  confirm
if [ "$confirm" = "y" ] ; then
  aws s3 cp "./app-$rand.zip" "s3://$AppUploadS3/"
  echo "[deploy.sh] Uploaded App Version: s3://$AppUploadS3/app-$rand.zip"
  aws elasticbeanstalk create-application-version --application-name "$AppName" --version-label "$versionlabel" --region $Region --source-bundle S3Bucket="$AppUploadS3",S3Key="app-$rand.zip" &> /dev/null
  aws elasticbeanstalk update-environment --application-name "$AppName" --environment-name "$EnvName" --version-label "$versionlabel" --region $Region &> /dev/null
  rm "./app-$rand.zip"
  echo "[deploy.sh] Deploying..."
else
  echo "[deploy.sh] Deployment Aborted."
  rm "./app-$rand.zip"
  exit 0;
fi

consoleurl="https://$Region.console.aws.amazon.com/elasticbeanstalk/home?region=\\$Region\\#\\/environment/dashboard\\?applicationName=$AppName&environmentName=$EnvName"
logsurl="https://$Region.console.aws.amazon.com/cloudwatch/home?region=\\$Region\\#logsV2\\:log-groups/log-group/\\\$252Faws\\\$252Felasticbeanstalk\\\$252F$EnvName"

# Wait for version to be released for 5 minutes
timeout=$((10 * 60))  # 5 minutes in seconds
interval=20  # Check every 20 seconds
elapsed=0

while [ $elapsed -lt $timeout ]; do
  sleep $interval
  elapsed=$((elapsed + interval))

  # Check if version is released
  environments=$( aws elasticbeanstalk describe-environments --application-name $AppName --environment-name $EnvName --region $Region )
  currentversionlabel=$( jq -r '.Environments[] | .VersionLabel' <<< $environments )
  if [ "$currentversionlabel" = "$versionlabel" ]; then
    
    # npm run eb -t "pm2 delete ssr"
    # npm run eb -t "cd /var/app/current && pm2 start npm --name ssr -i 0 --max-memory-restart 512 --cron-restart=\"*/10 * * * *\" -- start" # -i max same as -i 0 but depricated.

    echo "[deploy.sh] Version $versionlabel released successfully."

    break
  fi

  # Check if timeout reached
  if [ $elapsed -ge $timeout ]; then
    echo "[deploy.sh] Timeout reached. Deleting version $versionlabel."
    aws elasticbeanstalk delete-application-version --application-name $AppName --version-label "$versionlabel" --region $Region
    echo "[deploy.sh] Successfully removed version $versionlabel."
    break
  fi
done


# Run manually for now
# npm run eb
# cd /var/app/current
# sudo su root
# export COMPOSER_ALLOW_SUPERUSER=1 && /usr/bin/composer.phar install --optimize-autoloader --no-interaction