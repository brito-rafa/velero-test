kubectl patch deployment velero --patch "$(cat velero-debug-patch.yaml)" -n velero
