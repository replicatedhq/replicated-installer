build:
	docker build -t replicated/k8s-cni:0.6.0 .

push:
	docker push replicated/k8s-cni:0.6.0

# this gets run by airgap install script
unpack_example:
	docker run -v ${PWD}:/out replicated/k8s-cni:0.6.0
	mkdir -p cni
	tar xvf cni.tar.gz -C cni
