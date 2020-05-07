## Build and push an image

To trigger an image build via buildkite run the following command:

```
make build_ci IMAGE_TARGET=weave-kube/2.5.2 BUILDKITE_ACCESS_TOKEN=<your user token>
```

To obtain a user token visit https://buildkite.com/user/api-access-tokens/new.
The token must have permissions `read_builds` and `write_builds`.
