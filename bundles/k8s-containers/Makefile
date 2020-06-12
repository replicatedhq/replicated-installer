DATE=$(shell date +%Y%m%d)

include ../../images/manifest.mk

all: deps update_k8s_manifest build retag push

deps:
	go get github.com/linuxkit/linuxkit/src/cmd/linuxkit
	go get github.com/linuxkit/kubernetes || :

update_k8s_manifest_%: clean deps
	mkdir -p ./kubernetes-tmp-$*
	# CircleCI GOPATH is two paths separated by :
	cp -r $(shell echo ${GOPATH} | cut -d ':' -f 1)/src/github.com/linuxkit/kubernetes/pkg ./kubernetes-tmp-$*/
	cp -r $(shell echo ${GOPATH} | cut -d ':' -f 1)/src/github.com/linuxkit/kubernetes/.git ./kubernetes-tmp-$*/
	./mk-image-cache-lst-$* common > ./kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-common/images.lst
	./mk-image-cache-lst-$* control-plane > ./kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-control-plane/images.lst

build_%:
	$(eval common_image = $(shell linuxkit pkg build ./kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-common | grep 'Tagging linuxkit/kubernetes-docker-image-cache-common'| awk '{print $$2}'))
	docker tag ${common_image} replicated/k8s-images-common:$*-${DATE}
	$(eval control_image = $(shell linuxkit pkg build ./kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-control-plane | grep 'Tagging linuxkit/kubernetes-docker-image-cache-control-plane' | awk '{print $$2}'))
	docker tag ${control_image} replicated/k8s-images-control:$*-${DATE}

push_%:
	docker push replicated/k8s-images-common:$*-${DATE}
	docker push replicated/k8s-images-control:$*-${DATE}

clean:
	rm -rf ./kubernetes-tmp*
