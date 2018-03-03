build:
	docker build -t quay.io/replicated/k8s-packages:ubuntu-1604-v1.9.3 .
	docker build -t quay.io/replicated/k8s-packages:ubuntu-1604-v1.9.3.20180222 .

push:
	docker push quay.io/replicated/k8s-packages:ubuntu-1604-v1.9.3
	docker push quay.io/replicated/k8s-packages:ubuntu-1604-v1.9.3.20180222

# this gets run by airgap install script
unpack_example:
	docker run -v ${PWD}:/out replicated/k8s-packages:ubuntu-1604-v1.9.3
