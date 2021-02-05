function doBackupCase {

  case=$1
  echo "INFO: $case  Starting the back up case $case"
  echo ""
  echo "INFO: Delete testing cluster if it already exists"
  if [ "kind get clusters | grep $CLUSTER" ]; then
     kind delete cluster --name $CLUSTER
  fi

  echo ""
  echo "INFO: $case  Setting up testing cluster"

  # get tags from https://hub.docker.com/r/kindest/node/tags
  kind create cluster --name=$CLUSTER || exit 1
  #kind create cluster --image=kindest/node:v1.18.2 --name=$CLUSTER || exit 1

  echo "INFO: Onboarding testing CRD and CR - $case"
  curl -k -s https://raw.githubusercontent.com/brito-rafa/k8s-webhooks/master/examples-for-projectvelero/${case}/source-cluster.sh | bash

  # should return CRs
  kubectl get rockbands -A -o yaml

  # get the list of namespaces with rockband CRs
  casenamespaces=`kubectl get namespaces | grep rock | awk '{printf "%s%s",(NR>1?",":""),$1} END{print ""}'`

  # display message of the namespaces
  echo "INFO: $case Will backup the following namespaces: $casenamespaces"

  # installing velero default - want to make sure the velero GA is backing up all API Group releases
  echo ""
  echo "INFO: $case Installing Velero default"
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
  echo "INFO: $case Taking a Velero default backup"
  # this backup will be used to compare content 2251-patch and 1.3.1 default
  velerobackup="$case-$daystamp"
  velero backup create $velerobackup --include-namespaces $casenamespaces

  while  [ "$(velero backup get ${velerobackup} | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting backup... Break if it is taking longer than expected..." && velero backup get ${velerobackup} | tail -1 && sleep 10 ; done

  echo "INFO: $case backup complete"

}

function doRestoreCase {

  case=$1
  echo "INFO: $case Starting the restore case $case"

  echo ""
  echo "INFO: $case Delete testing cluster if it already exists"
  if [ "kind get clusters | grep $CLUSTER" ]; then
     kind delete cluster --name $CLUSTER
  fi

  echo ""
  echo "INFO: $case Setting up testing cluster - this is restore, we want the most modern k8s version"

  # get tags from https://hub.docker.com/r/kindest/node/tags - I want the newest cluster ever.
  kind create cluster --image=kindest/node:v1.19.7 --name=$CLUSTER || exit 1
  
  echo "INFO: $case Onboarding testing CRD and CR - $case"
  curl -k -s https://raw.githubusercontent.com/brito-rafa/k8s-webhooks/master/examples-for-projectvelero/${case}/target-cluster.sh | bash

  echo ""
  echo "INFO: $case Installing Velero $IMAGE"

  velero install \
    --features=EnableAPIGroupVersions \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.0.0 \
    --bucket $BUCKET \
    --prefix $PREFIX \
    --backup-location-config region=$REGION \
    --snapshot-location-config region=$REGION \
    --secret-file $SECRETFILE \
    --image $IMAGE || exit 2

  echo "INFO: $case Enabling --log-level debug on velero"
  kubectl patch deployment velero --patch "$(cat velero-allversions-patch.yaml)" -n velero

  # checking if there is the user-defined priority
  if  [ "$2" == "priority0" ]; then
    echo "INFO: $case Invoked restore with $2 , creating user-defined configmap"
    echo "   rockbands.music.example.io = v2beta1, v2beta2 " > restoreResourcesVersionPriority
    kubectl create configmap enableapigroupversions --from-file=restoreResourcesVersionPriority -n velero
    echo "INFO: $case config map"
    kubectl describe configmap enableapigroupversions -n velero
  fi

  echo ""
  velerotestingbackup="$case-$BackupDayToUse"
  echo "INFO: $case Waiting Velero controller to start..."

  while  [ "$(kubectl get pods -n velero | grep -i running | grep '1/1' |  wc -l | awk '{print $1}')" != "1" ]; do echo "Waiting Velero controller to start... Break if it is taking longer than expected..." && kubectl get pods -n velero  && sleep 10 ; done


  while  [ "$(velero backup get ${velerotestingbackup} 2>/dev/null | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting Velero controller to get backup ${velerotestingbackup} ... Break if it is taking multiple minutes ..." || sleep 10 && velero backup get ${velerotestingbackup} 2>/dev/null && sleep 30 ; done

  if  [ "$(velero backup get ${velerotestingbackup} | tail -1 | awk '{print $1}')" == "${velerotestingbackup}" ]; then
	velero restore create --from-backup ${velerotestingbackup} || exit 2
  else
	echo "ERROR: $case Could not find backup ${velerotestingbackup}"
	exit 1
  fi

  restorename=`velero restore get | grep -v NAME | grep $case | awk '{print $1}'`

  while  [ "$(velero restore get ${restorename} | tail -1 | awk '{print $3}')" != "Completed" ]; do echo "Waiting restore..." &&  velero restore get ${restorename} | tail -1 && sleep 10 ; done

  # it should show completed and with 0 errors
  velero restore get $restorename

  echo "INFO: $case Log messages regarding the priority"
  velero restore logs $restorename | grep -i APIGroupVersions | grep -i rockband

  echo "INFO: $case Custom Resources restored for $case"

}

function doAllBackups {
  echo "INFO: Creating all the backups"
  # see there for cases 
  doBackupCase case-a
  doBackupCase case-b
  doBackupCase case-c
  doBackupCase case-d
}

function doAllRestores {

  echo ""
  # see there for cases https://github.com/brito-rafa/k8s-webhooks/tree/master/examples-for-projectvelero

  doRestoreCase case-a
  echo "INFO: case-a success criteria - originally created v1alpha1 CR with converted fields on a v2beta1 CR"
  kubectl get rockbands.v2beta1.music.example.io beatles -n rockbands-v1alpha1 -o yaml | egrep -i "v1|v2beta1|beatles"

  doRestoreCase case-b
  echo "INFO: case-b success criteria - originally created v1 CR with converted fields on a v2beta2 CR"
  kubectl get rockbands.v2beta2.music.example.io beatles -n rockbands-v1 -o yaml | egrep -i "v1|v2beta2|lead|beatles"

  doRestoreCase case-c
  echo "INFO: case-c success criteria - originally created v1alpha1 CR with converted fields on a v2 CR"
  kubectl get rockbands.v2.music.example.io beatles -n rockbands-v1alpha1 -o yaml | egrep -i "v1|v2|lead|bass|beatles"

  doRestoreCase case-d
  echo "INFO: case-d success criteria - originally created v1 CR with converted fields on a v2beta2 CR"
  kubectl get rockbands.v2beta2.music.example.io -n rockbands-v1 -o yaml | egrep "v1|v2beta2|lead|bass|beatles"
  echo "INFO: case-d bass default field tells which version it came from - it should tell v2beta2"
  kubectl get rockbands.v2.music.example.io beatles -n rockbands-v1 -o yaml | grep bass

  doRestoreCase case-d priority0
  echo "INFO: case-d with priority0 success criteria - originally created v1 CR with converted fields on a v2beta1 CR"
  kubectl get rockbands.v2beta1.music.example.io beatles -n rockbands-v1 -o yaml | egrep -i "v1|v2|lead|bass|beatles"
  echo "INFO: case-d bass default field tells which version it came from - it should tell v2beta1"
  kubectl get rockbands.v2.music.example.io beatles -n rockbands-v1 -o yaml | grep bass

}


############
# script starts here
#############

if [ "$1" == "" ]; then
  echo "ERROR: At least one parameter expected:"
  echo "  \"backup\", \"restore\" or \"all\""
  exit 2
fi

timestamp=`date +%m%d%H%M`
daystamp=`date +%Y%m%d`

# parameters
# name of the kind cluster
export CLUSTER="${CLUSTER:-velero-dev}"

# variables for Velero
export BUCKET="${BUCKET:-brito-rafa-velero}"
export REGION="${REGION:-us-east-2}"
export SECRETFILE="${SECRETFILE:-/Users/rbrito/credentials-velero}" # bring your own credentials - see credentials-velero.example for an example
# I will put all backup/restores under this folder
export PREFIX="${PREFIX:-EnableMultiAPIGroups}"

# Velero Image to be tested (only during restore)
export IMAGE="${IMAGE:-projects.registry.vmware.com/tanzu_migrator/velero-pr3133:0.0.5}"
echo "INFO: Restore Testing the following image: $IMAGE"


echo "INFO: Starting testing script - it uses all cases from https://github.com/brito-rafa/k8s-webhooks/tree/master/examples-for-projectvelero"

export BackupDayToUse=$daystamp

if [ "$1" == "all" ] || [ "$1" == "backup" ]; then
  doAllBackups
fi

if [ "$1" == "all" ] || [ "$1" == "restore" ]; then
  echo "INFO: Starting restore"
  if [ "$2" != "" ]; then
    export BackupDayToUse=$2
    echo "INFO: Using backup from $BackupDayToUse day"
  fi
  doAllRestores
fi
