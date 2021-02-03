#set -x

function doBackupCase {

  case=$1
  echo "INFO: Starting the back up case $case"
  echo ""
  echo "INFO: Delete testing cluster if it already exists"
  if [ "kind get clusters | grep $CLUSTER" ]; then
     kind delete cluster --name $CLUSTER
  fi

  echo ""
  echo "INFO: Setting up testing cluster"

  # get tags from https://hub.docker.com/r/kindest/node/tags
  kind create cluster --name=$CLUSTER || exit 1
  #kind create cluster --image=kindest/node:v1.18.2 --name=$CLUSTER || exit 1

  # the following is not really since we are recreating the kind cluster
  echo "INFO: Removing any prior velero, namespaces, CR and CRD"
  for i in `kubectl get namespace | egrep "rockband|cert-manager|music|velero" | awk '{print $1}'`; do
    kubectl delete namespace $i
  done
  kubectl delete crd rockbands.music.example.io

  echo "INFO: Onboarding testing CRD and CR - $case"
  curl -k -s https://raw.githubusercontent.com/brito-rafa/k8s-webhooks/master/examples-for-projectvelero/${case}/source-cluster.sh | bash

  # should return CRs
  kubectl get rockbands -A -o yaml

  # get the list of namespaces with rockband CRs
  casenamespaces=`kubectl get namespaces | grep rock | awk '{printf "%s%s",(NR>1?",":""),$1} END{print ""}'`

  # display message of the namespaces
  echo "Will backup the following namespaces: $casenamespaces"

  # setting up velero
  export BUCKET=brito-rafa-velero
  export REGION=us-east-2
  export SECRETFILE=/Users/rbrito/credentials-velero # bring your own credentials - see credentials-velero.example for an example

  export PREFIX=EnableMultiAPIGroups

  # installing velero default - want to make sure the velero GA is backing up all API Group releases
  echo ""
  echo "INFO: Installing Velero default"
  velero install \
    --features=EnableAPIGroupVersions \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.0.0 \
    --bucket $BUCKET \
    --prefix $PREFIX \
    --backup-location-config region=$REGION \
    --snapshot-location-config region=$REGION \
    --secret-file $SECRETFILE || exit 2

  echo ""
  echo "INFO: Taking a Velero default backup"
  # this backup will be used to compare content 2251-patch and 1.3.1 default
  velerobackup="$case-$daystamp"
  velero backup create $velerobackup --include-namespaces $casenamespaces

  while  [ "$(velero backup get ${velerobackup} | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting backup... Break if it is taking longer than expected..." && velero backup get ${velerobackup} | tail -1 && sleep 10 ; done

  echo "INFO: $case backup complete"

}

#############
# script starts here
#############

timestamp=`date +%m%d%H%M`
daystamp=`date +%Y%m%d`

export CLUSTER=velero-dev

echo "Info: Starting testing script"

echo ""
# see there for cases https://github.com/brito-rafa/k8s-webhooks/tree/master/examples-for-projectvelero
doBackupCase case-a
doBackupCase case-b
doBackupCase case-c
doBackupCase case-d


