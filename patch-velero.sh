kubectl patch deployment velero --patch "$(cat velero-allversions-patch.yaml)" -n velero
