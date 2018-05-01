all: deps update_k8s_manifest build retag push

deps:
	go get github.com/linuxkit/linuxkit/src/cmd/linuxkit
	go get github.com/linuxkit/kubernetes || :

update_k8s_manifest: clean
	mkdir -p ./kubernetes-tmp
	cp -r ${GOPATH}/src/github.com/linuxkit/kubernetes/pkg ./kubernetes-tmp/
	cp -r ${GOPATH}/src/github.com/linuxkit/kubernetes/.git ./kubernetes-tmp/
	./mk-image-cache-lst common > ./kubernetes-tmp/pkg/kubernetes-docker-image-cache-common/images.lst
	./mk-image-cache-lst control-plane > ./kubernetes-tmp/pkg/kubernetes-docker-image-cache-control-plane/images.lst

build:
	linuxkit pkg build ./kubernetes-tmp/pkg/kubernetes-docker-image-cache-common
	linuxkit pkg build ./kubernetes-tmp/pkg/kubernetes-docker-image-cache-control-plane

retag:
	docker tag linuxkit/kubernetes-docker-image-cache-common:a4eb1313407e72fda5789b9ca604997650126539-dirty-amd64 quay.io/replicated/k8s-images-common:v1.9.3-20180501
	docker tag linuxkit/kubernetes-docker-image-cache-control-plane:e41541ca040a0001e02dd5c8ac40e0ae38110a7a-dirty-amd64 quay.io/replicated/k8s-images-control:v1.9.3-20180222



push:
	docker push quay.io/replicated/k8s-images-common:v1.9.3-20180501
	docker push quay.io/replicated/k8s-images-control:v1.9.3-20180222

clean:
	rm -rf ./kubernetes-tmp
