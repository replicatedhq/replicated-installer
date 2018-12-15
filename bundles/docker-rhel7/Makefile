DATE=$(shell date +%Y%m%d)

build:
	docker build -t quay.io/replicated/docker-packages:rhel7-v17.09.1-${DATE} .

push:
	docker push quay.io/replicated/docker-packages:rhel7-v17.09.1-${DATE}

print_layer_id:
	@docker save quay.io/replicated/docker-packages:rhel7-v17.09.1-${DATE} | tar -t | grep layer.tar | cut -d'/' -f1

export: build
	docker tag quay.io/replicated/docker-packages:rhel7-v17.09.1-${DATE} replicated/docker-packages:rhel7-v17.09.1
	docker save replicated/docker-packages:rhel7-v17.09.1 > packages-docker-rhel7.tar

# this gets run by airgap install script
unpack_example: export
	rm -rf image/
	mkdir -p image/
	tar xvf packages-docker-rhel7.tar -C image
	tar xvf image/cdb00b5dc544c1744c1d22bfdfb6326bf95b927ab4877e518eb6ba93d1f9c30f/layer.tar
