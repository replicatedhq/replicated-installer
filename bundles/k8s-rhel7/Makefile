build:
	docker build -t replicated/k8s-packages:rhel-7-v1.9.3 .
	docker build -t replicated/k8s-packages:rhel-7-v1.9.3.20180227 .

push:
	docker push replicated/k8s-packages:rhel-7-v1.9.3
	docker push replicated/k8s-packages:rhel-7-v1.9.3.20180227

export: build
	docker tag replicated/k8s-packages:rhel-7-v1.9.3 replicated/k8s-packages:rhel-7-v1.9.3
	docker save replicated/k8s-packages:rhel-7-v1.9.3 > packages-kubernetes-rhel7.tar

# this gets run by airgap install script
unpack_example: build
	docker run -v ${PWD}:/out replicated/k8s-packages:rhel-7-v1.9.3
