# this builds CNI v0.6.0, but we tag it with the kubernetes version to keep things simpler in install-scripts
build:
	docker build -t quay.io/replicated/k8s-cni:v1.9.3 .

push:
	docker push quay.io/replicated/k8s-cni:v1.9.3

# this gets run by airgap install script
unpack_example:
	docker run -v ${PWD}:/out quay.io/replicated/k8s-cni:v1.9.3
	mkdir -p cni
	tar xvf cni.tar.gz -C cni
