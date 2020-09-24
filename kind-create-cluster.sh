#set -x

# kind-create-cluster.sh
# - basically a quick test script to install velero 1.4/1.5 and create a backup to aws

timestamp=`date +%m%d%H%M`

export CLUSTER=velero-dev

echo ""
echo "INFO: Delete testing cluster if it already exists"
if [ "kind get clusters | grep $CLUSTER" ]; then
   kind delete cluster --name $CLUSTER
fi

# first create a kind cluster
echo ""
echo "INFO: create cluster"
kind create cluster --name=$CLUSTER || exit 1
#kind create cluster --image=kindest/node:v1.19.0 --name=$CLUSTER || exit 1

# setting up velero
export BUCKET=test-velero-migration
export REGION=us-east-2
export SECRETFILE=credentials-dave
export VERSION=dev-dave-0923a
export PREFIX=$VERSION

# ----
# install velero 1.4 and create backup
# ----

export IMAGE=velero/velero:v1.4.0

echo ""
echo "INFO: Installing 1.4 cluster"
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:latest \
  --bucket $BUCKET \
  --prefix $PREFIX \
  --backup-location-config region=$REGION \
  --snapshot-location-config region=$REGION \
  --secret-file $SECRETFILE \
  --image $IMAGE

echo ""
echo "INFO: Creating 1.4 backup"
velerodefaultbackup="clusterlevel-1-4-$timestamp"
velero backup create $velerodefaultbackup

while  [ "$(velero backup get ${velerodefaultbackup} | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting backup... Break if it is taking longer than expected..." && velero backup get ${velerodefaultbackup} | tail -1 && sleep 10 ; done

echo "INFO: 1.4 backup complete"

# delete/recreate kind cluster
kind delete cluster --name=$CLUSTER 
echo ""
echo "INFO: create cluster"
kind create cluster --name=$CLUSTER || exit 1

# ----
# install velero 1.5 and create backup
# ----

export IMAGE=velero/velero:latest

echo ""
echo "INFO: Installing 1.5 cluster"  

velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:latest \
  --bucket $BUCKET \
  --prefix $PREFIX \
  --backup-location-config region=$REGION \
  --snapshot-location-config region=$REGION \
  --secret-file $SECRETFILE \
  --image $IMAGE

echo ""
echo "INFO: Creating 1.5 backup"
velerotestingbackup="clusterlevel-1-5-$timestamp"
velero backup create ${velerotestingbackup}

while  [ "$(velero backup get ${velerotestingbackup} | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting backup... Break if it is taking longer than expected..." && velero backup get ${velerotestingbackup} | tail -1 && sleep 10 ; done

echo "INFO: 1.5 backup complete"

#echo ""
#echo "INFO: Deleting cluster"
#kind delete cluster --name=$CLUSTER
