DATE=$(shell date +%Y%m%d)

deps:
	curl -Lo /tmp/linuxkit-linux-amd64 https://github.com/linuxkit/linuxkit/releases/download/v0.7/linuxkit-linux-amd64
	cp /tmp/linuxkit-linux-amd64 $(GOPATH)/bin/linuxkit
	chmod +x $(GOPATH)/bin/linuxkit

update_k8s_manifest_%: clean deps
	git clone https://github.com/linuxkit/kubernetes.git /tmp/kubernetes
	mkdir -p /tmp/kubernetes-tmp-$*
	# CircleCI GOPATH is two paths separated by :
	cp -r /tmp/kubernetes/pkg /tmp/kubernetes-tmp-$*/
	cp -r /tmp/kubernetes/.git /tmp/kubernetes-tmp-$*/
	./mk-image-cache-lst-$* common > /tmp/kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-common/images.lst
	./mk-image-cache-lst-$* control-plane > /tmp/kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-control-plane/images.lst

build_%:
	linuxkit pkg build /tmp/kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-common
	$(eval common_image = $(shell linuxkit pkg show-tag /tmp/kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-common))
	docker tag ${common_image} replicated/k8s-images-common:$*-${DATE}
	linuxkit pkg build /tmp/kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-control-plane
	$(eval control_image = $(shell linuxkit pkg show-tag /tmp/kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-control-plane))
	docker tag ${control_image} replicated/k8s-images-control:$*-${DATE}

push_%:
	docker push replicated/k8s-images-common:$*-${DATE}
	docker push replicated/k8s-images-control:$*-${DATE}

clean:
	rm -rf /tmp/kubernetes-tmp* /tmp/kubernetes
