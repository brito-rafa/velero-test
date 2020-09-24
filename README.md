# Misc tools for Velero Testing

- 2251-dev-test.sh                
    - script for testing api groups
- credentials-velero.example      
    - format of aws cred file
- 2251-updated.sh                    
    - modification of 2251-dev-test.sh
    - more of a version update
- kind-create-cluster.sh         
    - test script to create cluster, install velero 1.4/1.5, and backup
- install-plugins.sh
    - script to install velero, deploy sample plugins, backup using plugins
- myexample-test.yaml
    - horizontal pod scaling example
    - called within 2251-dev-test.sh and 2251-updated.sh
- patch-velero.sh
- README.md                       
    - this file
- velero-allversions-patch.yaml
    - enable API group versions
    - called within 2251-dev-test.sh and 2251-updated.sh
- velero-patch.yaml

