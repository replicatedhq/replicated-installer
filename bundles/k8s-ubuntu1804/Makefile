DATE=$(shell date +%Y%m%d)

v1.13.5:
	docker build --build-arg VERSION=1.13.5 \
		-t quay.io/replicated/k8s-packages:ubuntu-1804-v1.13.5-${DATE} .
	docker push quay.io/replicated/k8s-packages:ubuntu-1804-v1.13.5-${DATE}
