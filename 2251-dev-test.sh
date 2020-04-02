#set -x

timestamp=`date +%m%d%H%M`

echo ""
echo "INFO: Setting up testing cluster"

kind create cluster --image=kindest/node:v1.16.4 --name velero-dev || exit 1

# onboarding sample all with items that belong to multiple
# api groups, ie horizontalpodscaling
echo ""
echo "INFO: Onboarding testing app"
kubectl apply -f myexample-test.yaml

# should return one object
kubectl get hpa php-apache-autoscaler -n myexample 

# setting up velero
export BUCKET=brito-rafa-velero
export REGION=us-east-2
export SECRETFILE=credentials-velero

export VERSION=dev-2251-0401-a
export PREFIX=$VERSION

# installing with 1.3.1 initially
echo ""
echo "INFO: Installing Velero default"
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.0.0 \
  --bucket $BUCKET \
  --prefix $PREFIX \
  --backup-location-config region=$REGION \
  --snapshot-location-config region=$REGION \
  --secret-file $SECRETFILE 

echo ""
echo "INFO: Taking a Velero default backup"
# this backup will be used to compare content 2251-patch and 1.3.1 default
velerodefaultbackup="clusterlevel-default-1-3-1-$timestamp"
velero backup create $velerodefaultbackup

while  [ "$(velero backup get ${velerodefaultbackup} | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting backup... Break if it is taking longer than expected..." && velero backup get ${velerodefaultbackup} | tail -1 && sleep 5 ; done

echo "INFO: Default backup complete"

# Deleting current velero deployment and installing with the patched release
echo ""
echo "INFO: Installing Velero testing version"
kubectl delete namespace velero

export IMAGE=quay.io/brito_rafa/velero:$VERSION

velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.0.0 \
  --bucket $BUCKET \
  --prefix $PREFIX \
  --backup-location-config region=$REGION \
  --snapshot-location-config region=$REGION \
  --secret-file $SECRETFILE \
  --image $IMAGE

echo "INFO: Image running"
# showing that velero is now running with patch version
kubectl get deployment velero -n velero -o yaml | grep -m 1 'image:'

echo ""
echo "INFO: Creating testing backup"
# create the first backup with the new image
velerotestingbackup="clusterlevel-$VERSION-$timestamp"
velero backup create ${velerotestingbackup}

while  [ "$(velero backup get ${velerotestingbackup} | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting backup... Break if it is taking longer than expected..." && velero backup get ${velerotestingbackup} | tail -1 && sleep 10 ; done

echo ""
echo "INFO: Testing restore..."

kubectl delete namespace myexample

# restoring from backup taken with 2251-patch
velero restore create --from-backup ${velerotestingbackup}

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

# the intent is to verify the preferred version from the patch matches the default 1.3.1
echo ""
echo "INFO: Comparing the two backups - ignore errors on velero objects and time based objects - some might not exist among the two backups"
echo ""
for i in `find resources/ -type f -not -path "*/events/*"`; do origprefversion=`cat ${i} | awk -F\" '{print $4}'` && patchprefversion=`cat ../${velerotestingbackup}/${i} | awk -F\" '{print $4}'` && [[ $origprefversion != $patchprefversion ]] && echo "${i} not equal"; done

cd ../../

echo ""
echo "INFO: Deleting cluster"
kind delete cluster --name=velero-dev
