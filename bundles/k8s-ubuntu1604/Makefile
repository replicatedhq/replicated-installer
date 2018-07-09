DATE=$(shell date +%Y%m%d)

v1.9.3:
	docker build --build-arg VERSION=1.9.3 \
		-t quay.io/replicated/k8s-packages:ubuntu-1604-v1.9.3-${DATE} .
	docker push quay.io/replicated/k8s-packages:ubuntu-1604-v1.9.3-${DATE}

v1.10.5:
	docker build --build-arg VERSION=1.10.5 \
		-t quay.io/replicated/k8s-packages:ubuntu-1604-v1.10.5-${DATE} .
	docker push quay.io/replicated/k8s-packages:ubuntu-1604-v1.10.5-${DATE}

v1.11.0:
	docker build --build-arg VERSION=1.11.0 \
		-t quay.io/replicated/k8s-packages:ubuntu-1604-v1.11.0-${DATE} .
	docker push quay.io/replicated/k8s-packages:ubuntu-1604-v1.11.0-${DATE}
