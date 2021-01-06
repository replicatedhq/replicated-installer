Kubernetes Containers
===================

This is mostly a placeholder directory, the production kubernetes
container bundle is generated using https://github.com/linuxkit/kubernetes.

Example for v1.9.3 (dev/testing only)
```
make update_k8s_manifest_v1.9.3
make build_v1.9.3
make push_v1.9.3
```

Release bundles must be built on CI server with the following command
```
curl -u ${CIRCLE_CI_INSTALL_SCRIPTS_TOKEN}: \
     -d build_parameters[CIRCLE_JOB]=build_k8s_bundles \
     -d build_parameters[K8S_VERSION]=v1.15.12 \
     https://circleci.com/api/v1.1/project/github/replicatedhq/replicated-installer/tree/<my-branch>
```

Steps
------

See Makefile

