DATE=$(shell date +%Y%m%d)

v1.9.3:
	docker build --build-arg VERSION=1.9.3 \
		-t quay.io/replicated/k8s-packages:rhel-74-v1.9.3-${DATE} .
	docker push quay.io/replicated/k8s-packages:rhel-74-v1.9.3-${DATE}

v1.10.6:
	docker build --build-arg VERSION=1.10.6 \
		-t quay.io/replicated/k8s-packages:rhel-74-v1.10.6-${DATE} .
	docker push quay.io/replicated/k8s-packages:rhel-74-v1.10.6-${DATE}

v1.11.1:
	docker build --build-arg VERSION=1.11.1 \
		-t quay.io/replicated/k8s-packages:rhel-74-v1.11.1-${DATE} .
	docker push quay.io/replicated/k8s-packages:rhel-74-v1.11.1-${DATE}
