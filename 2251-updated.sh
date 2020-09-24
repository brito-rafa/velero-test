#set -x

# 2251-updated.sh
# - show that you can migrate across multiple k8s versions (i.e.  k8s 1.18 to k8s 1.19)
# - this is a slightly updated version of the 2251-dev-test script
# - updated kindest/node versions
# - updated velero versions

timestamp=`date +%m%d%H%M`

export CLUSTER=velero-dev

echo ""
echo "INFO: Delete testing cluster if it already exists"
if [ "kind get clusters | grep $CLUSTER" ]; then
   kind delete cluster --name $CLUSTER
fi

echo ""
echo "INFO: Setting up testing cluster"

# get tags from https://hub.docker.com/r/kindest/node/tags
# first create a kind cluster with a set version of v1.18.2 - you will upgrade this later
#kind create cluster --name=$CLUSTER || exit 1
kind create cluster --image=kindest/node:v1.18.2 --name=$CLUSTER || exit 1

# onboarding sample all with items that belong to multiple
# api groups, ie horizontalpodscaling
echo ""
echo "INFO: Onboarding testing app"
kubectl apply -f myexample-test.yaml

# should return one object
kubectl get hpa php-apache-autoscaler -n myexample 

# Here's the aws structure
# BUCKET = name of S3 bucket
# PREFIX = name of folder under S3 bucket (BUCKET)
# then there is a folder named "backups" or "restore" under PREFIX
# VERSION = the folder under backups that contains the json gzips

# setting up velero
export BUCKET=test-velero-migration
export REGION=us-east-2
export SECRETFILE=credentials-dave   # bring your own credentials - see credentials-velero.example for an example
export VERSION=dev-dave-0923b
export PREFIX=$VERSION

export VELEROTAG=latest
export IMAGE=velero/velero:$VELEROTAG

# installing with velero latest initially
echo ""
echo "INFO: Installing Velero $VELEROTAG"
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:$VELEROTAG \
  --bucket $BUCKET \
  --prefix $PREFIX \
  --backup-location-config region=$REGION \
  --snapshot-location-config region=$REGION \
  --secret-file $SECRETFILE \
  --image $IMAGE
  

echo ""
echo "INFO: Taking a Velero $VELEROTAG backup"
# this backup will be used to compare content from dockerhub velero image and 1.5 default
velerodefaultbackup="clusterlevel-$VELEROTAG-$timestamp"
velero backup create $velerodefaultbackup

while  [ "$(velero backup get ${velerodefaultbackup} | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting backup... Break if it is taking longer than expected..." && velero backup get ${velerodefaultbackup} | tail -1 && sleep 10 ; done

echo "INFO: Velero $VELEROTAG backup complete"

# Deleting current velero deployment and installing with the patched release
echo ""
echo "INFO: Installing Velero local build version"
kubectl delete namespace velero

# Note:  this velero install adds the "--image" flag which uses the image in dockerhub
export TAG=dev-0922
export DHIMAGE=docker.io/bikeskinh/velero:$TAG

velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:latest \
  --bucket $BUCKET \
  --prefix $PREFIX \
  --backup-location-config region=$REGION \
  --snapshot-location-config region=$REGION \
  --secret-file $SECRETFILE \
  --image $DHIMAGE

echo "INFO: Image running"
# showing that velero is now running with patch version
kubectl get deployment velero -n velero -o yaml | grep -m 1 'image:'

# enable API GroupVersions
echo "INFO: Enabling All Versions backup"
kubectl patch deployment velero --patch "$(cat velero-allversions-patch.yaml)" -n velero || exit 1

echo ""
echo "INFO: Creating $TAG backup"
# create the first backup with the new image
velerotestingbackup="clusterlevel-$TAG-$timestamp"
velero backup create ${velerotestingbackup}

while  [ "$(velero backup get ${velerotestingbackup} | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting backup... Break if it is taking longer than expected..." && velero backup get ${velerotestingbackup} | tail -1 && sleep 10 ; done

echo "INFO: Deleting initial cluster..."
kind delete cluster --name=$CLUSTER

echo ""
echo "INFO: Testing restore..."

echo ""
echo "INFO: Creating a brand new k8s cluster, with a higher k8s version..."
#kind create cluster --name=$CLUSTER || exit 1
kind create cluster --image=kindest/node:v1.19.0 --name $CLUSTER || exit 1

echo ""
echo "INFO: Installing Velero $IMAGE"
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:latest \
  --bucket $BUCKET \
  --prefix $PREFIX \
  --backup-location-config region=$REGION \
  --snapshot-location-config region=$REGION \
  --secret-file $SECRETFILE \
  --image $IMAGE

echo "INFO: Waiting Velero controller to start..."

while  [ "$(velero backup get ${velerotestingbackup} 2>/dev/null | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting Velero controller... Break if it is taking multiple minutes ..." && sleep 30 ; done

echo "INFO:  Restoring from backup taken with $DHIMAGE"

# restore from dockerhub image backup

# restoring from backup taken with dockerhub image
# something changed in the "velero backup get" logic from rafael's test
# the order returned from "velero backup get" looks like it is sorted in alphabetical order and tail -1 will not always return the correct one
# added ${velerotestingbackup} to "velero backup get"
if  [ "$(velero backup get ${velerotestingbackup} | tail -1 | awk '{print $1}')" == "${velerotestingbackup}" ]; then
	velero restore create --from-backup ${velerotestingbackup} || exit 2
else
	echo "ERROR: Could not find backup ${velerotestingbackup}"
	exit 1
fi

restorename=`velero restore get | grep -v NAME | awk '{print $1}'`

while  [ "$(velero restore get ${restorename} | tail -1 | awk '{print $3}')" != "Completed" ]; do echo "Waiting restore..." &&  velero restore get ${restorename} | tail -1 && sleep 10 ; done

# it should show completed and with 0 errors
velero restore get $restorename

# getting the same object, it should match the name
# if so, the patch is backward compatible
kubectl get hpa php-apache-autoscaler -n myexample 

# Checking restore logs for errors
velero restore logs $restorename | grep -i error

# now comparing the contents among the two backups

mkdir -p test/${velerotestingbackup}
cd test/${velerotestingbackup}
velero backup download ${velerotestingbackup}
tar -xvzf ${velerotestingbackup}-data.tar.gz

cd ../../

mkdir -p test/${velerodefaultbackup}
cd test/${velerodefaultbackup}
velero backup download ${velerodefaultbackup}
tar -xvzf ${velerodefaultbackup}-data.tar.gz

# the intent is to verify the preferred version from the local build matches the default
echo ""
echo "INFO: Comparing the two backups - ignore errors on velero objects and time based objects - some might not exist among the two backups"
echo ""
# comparing the version of each item - field #4 of the json
for i in `find resources/ -type f -not -path "*/events/*"`; do origprefversion=`cat ${i} | awk -F\" '{print $4}'` && patchprefversion=`cat ../${velerotestingbackup}/${i} 2>/dev/null | awk -F\" '{print $4}'` && [[ $origprefversion != $patchprefversion ]] && echo "${i} not equal"; done

cd ../../

# don't delete the cluster in case you want to look at it
#echo ""
#echo "INFO: Deleting cluster"
#kind delete cluster --name=$CLUSTER
