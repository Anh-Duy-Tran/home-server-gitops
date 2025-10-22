TODO: After the auto restore config run, it fail to watch the restore resource

```
E1022 01:48:47.666288      31 reflector.go:205] "Failed to watch" err="restores.velero.io \"auto-restore-1761097727\" is forbidden: │
│  User \"system:serviceaccount:velero:velero-restore-job\" cannot watch resource \"restores\" in API group \"velero.io\" in the name │
│ space \"velero\"" reflector="k8s.io/client-go/tools/watch/informerwatcher.go:162" type="*unstructured.Unstructured"
```
