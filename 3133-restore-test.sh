#set -x

function doRestoreCase {

  case=$1
  echo "INFO: Starting the restore case $case"

  echo ""
  echo "INFO: Delete testing cluster if it already exists"
  if [ "kind get clusters | grep $CLUSTER" ]; then
     kind delete cluster --name $CLUSTER
  fi

  echo ""
  echo "INFO: Setting up testing cluster"

  # get tags from https://hub.docker.com/r/kindest/node/tags - I want the newest cluster ever.
  kind create cluster --image=kindest/node:v1.19.7 --name=$CLUSTER || exit 1

  echo "INFO: Onboarding testing CRD and CR - $case"
  curl -k -s https://raw.githubusercontent.com/brito-rafa/k8s-webhooks/master/examples-for-projectvelero/${case}/target-cluster.sh | bash

  # setting up velero
  export BUCKET=brito-rafa-velero
  export REGION=us-east-2
  export SECRETFILE=/Users/rbrito/credentials-velero # bring your own credentials - see credentials-velero.example for an example

  export PREFIX=EnableMultiAPIGroups

  export IMAGE=projects.registry.vmware.com/tanzu_migrator/velero-pr3133:0.0.3

  echo ""
  echo "INFO: Installing Velero $IMAGE"

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

  echo "INFO: Enabling --log-level debug on velero"
  kubectl patch deployment velero --patch "$(cat velero-allversions-patch.yaml)" -n velero

  # checking if there is the user-defined priority
  if  [ "$2" == "priority0" ]; then
    echo "INFO: Invoked restore with $2 , creating user-define configmap"
    echo "rockbands.music.example.io=v2beta1,v2beta2" | tr -d '\n' > restoreResourcesVersionPriority
    kubectl create configmap enableapigroupversions --from-file=restoreResourcesVersionPriority -n velero
    echo "INFO: config map"
    kubectl describe configmap enableapigroupversions -n velero
  fi

  echo ""
  velerotestingbackup="$case-$daystamp"
  echo "INFO: Waiting Velero controller to start..."

  while  [ "$(kubectl get pods -n velero | grep -i running | grep '1/1' |  wc -l | awk '{print $1}')" != "1" ]; do echo "Waiting Velero controller to start... Break if it is taking longer than expected..." && kubectl get pods -n velero  && sleep 10 ; done


  while  [ "$(velero backup get ${velerotestingbackup} 2>/dev/null | tail -1 | awk '{print $2}')" != "Completed" ]; do echo "Waiting Velero controller to get backup... Break if it is taking multiple minutes ..." && velero backup get ${velerotestingbackup} 2>/dev/null && sleep 30 ; done

  if  [ "$(velero backup get ${velerotestingbackup} | tail -1 | awk '{print $1}')" == "${velerotestingbackup}" ]; then
	velero restore create --from-backup ${velerotestingbackup} || exit 2
  else
	echo "ERROR: Could not find backup ${velerotestingbackup}"
	exit 1
  fi

  restorename=`velero restore get | grep -v NAME | grep $case | awk '{print $1}'`

  while  [ "$(velero restore get ${restorename} | tail -1 | awk '{print $3}')" != "Completed" ]; do echo "Waiting restore..." &&  velero restore get ${restorename} | tail -1 && sleep 10 ; done

  # it should show completed and with 0 errors
  velero restore get $restorename

  echo "INFO: Log messages regarding the priority"
  velero restore logs $restorename | grep -i APIGroupVersions

  echo "INFO: Custom Resources restored for $case"

}

#############
# script starts here
#############

timestamp=`date +%m%d%H%M`
#daystamp=`date +%Y%m%d`
daystamp="20210202"

export CLUSTER=velero-dev

echo "Info: Starting restore testing script"

echo ""
# see there for cases https://github.com/brito-rafa/k8s-webhooks/tree/master/examples-for-projectvelero
#doRestoreCase case-a

#echo "INFO: case-a success criteria is see originally created v1alpha1 CR with all fields as v2beta1"
#kubectl get rockbands.v2beta1.music.example.io beatles -n rockbands-v1alpha1 -o yaml | egrep "v1|v2beta1|lead|beatles"

#doRestoreCase case-b
#echo "INFO: case-b success criteria is see originally created v1 CR with all fields as v2beta2"
#kubectl get rockbands.v2beta2.music.example.io beatles -n rockbands-v1 -o yaml | egrep "v1|v2beta2|lead|beatles"

#doRestoreCase case-c
#echo "INFO: case-c success criteria is see originally created v1alpha1 CR with all fields as v2"
#kubectl get rockbands.v2.music.example.io beatles -n rockbands-v1alphav1 -o yaml | egrep -i "v1|v2|lead|bass|beatles"

#doRestoreCase case-d
#echo "INFO: case-d success criteria is see originally created v1 CR with all fields as v2"
#kubectl get rockbands.v2.music.example.io beatles -n rockbands-v1 -o yaml | egrep -i "v1|v2|lead|bass|beatles"
#echo "INFO: case-d success criteria is see bass field telling which version it came from"
#kubectl get rockbands.v2.music.example.io beatles -n rockbands-v1 -o yaml | grep bass

doRestoreCase case-d priority0
echo "INFO: case-d with priority0 success criteria is see originally created v1 CR with all fields as v2"
kubectl get rockbands.v2.music.example.io beatles -n rockbands-v1 -o yaml | egrep -i "v1|v2|lead|bass|beatles"
echo "INFO: case-d with priority0 is see bass field telling which version it came from"
kubectl get rockbands.v2.music.example.io beatles -n rockbands-v1 -o yaml | grep bass


