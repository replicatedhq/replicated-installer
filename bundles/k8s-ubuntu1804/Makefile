DATE=$(shell date +%Y%m%d)

v1.13.5:
	docker build --build-arg VERSION=1.13.5 \
		-t quay.io/replicated/k8s-packages:ubuntu-1804-v1.13.5-${DATE} .
	docker push quay.io/replicated/k8s-packages:ubuntu-1804-v1.13.5-${DATE}

v1.14.3:
	docker build --build-arg VERSION=1.14.3 \
		-t quay.io/replicated/k8s-packages:ubuntu-1804-v1.14.3-${DATE} .
	docker push quay.io/replicated/k8s-packages:ubuntu-1804-v1.14.3-${DATE}

v1.15.0:
	docker build --build-arg VERSION=1.15.0 \
		-t quay.io/replicated/k8s-packages:ubuntu-1804-v1.15.0-${DATE} .
	docker push quay.io/replicated/k8s-packages:ubuntu-1804-v1.15.0-${DATE}
