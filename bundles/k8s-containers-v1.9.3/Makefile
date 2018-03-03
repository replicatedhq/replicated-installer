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
	docker tag linuxkit/kubernetes-docker-image-cache-common:32f09de29fa8c517e14d8d733f79e467ab5eaf7d-dirty-amd64 replicated/k8s-images-common:v1.9.3-20180222
	docker tag linuxkit/kubernetes-docker-image-cache-control-plane:003bc342571352ecdf16f720f841cc923b2e32f0-dirty-amd64 replicated/k8s-images-control:v1.9.3-20180222



push:
	docker push replicated/k8s-images-common:v1.9.3-20180222
	docker push replicated/k8s-images-control:v1.9.3-20180222

clean:
	rm -rf ./kubernetes-tmp
