#set -x

# install-plugins.sh
# - install velero
# - deploy sample plugins
# - backup the kind cluster using the sample plugins

timestamp=`date +%m%d%H%M`

export CLUSTER=velero-plugin

echo ""
echo "INFO: Delete testing cluster if it already exists"
if [ "kind get clusters | grep $CLUSTER" ]; then
   kind delete cluster --name $CLUSTER
fi

# first create a kind cluster
echo ""
echo "INFO: create cluster"
kind create cluster --image=kindest/node:v1.19.0 --name=$CLUSTER || exit 1

# setting up velero
export BUCKET=test-velero-plugin
export REGION=us-east-2
export SECRETFILE=credentials-dave
export VERSION=plugin-0923
export PREFIX=$VERSION

# ----
# install velero 1.5.1 and create backup
# ----

export IMAGE=velero/velero:latest

echo ""
echo "INFO: Installing 1.5.1 cluster"  

velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:latest \
  --bucket $BUCKET \
  --prefix $PREFIX \
  --backup-location-config region=$REGION \
  --snapshot-location-config region=$REGION \
  --secret-file $SECRETFILE \
  --image $IMAGE


# deploy the plugins
# format velero plugin add <registry>/<image>:<tag>
echo ""
echo "deploy the plugins..."
velero plugin add docker.io/bikeskinh/velero-plugin-scc-2-psp:0922-a

echo ""
echo "INFO: Creating 1.5.1 backup"
velerotestingbackup="backup-1-5-$timestamp"
velero backup create ${velerotestingbackup}

while  [ "$(velero backup get ${velerotestingbackup} | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting backup... Break if it is taking longer than expected..." && velero backup get ${velerotestingbackup} | tail -1 && sleep 10 ; done

echo "INFO: 1.5 backup complete"

#echo ""
#echo "INFO: Deleting cluster"
#kind delete cluster --name=$CLUSTER
