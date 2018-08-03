DATE=$(shell date +%Y%m%d)

build:
	docker build -t quay.io/replicated/docker-packages:rhel-7.4-v1.12.6-${DATE} .

push:
	docker push quay.io/replicated/docker-packages:rhel-7.4-v1.12.6-${DATE}

print_layer_id:
	@docker save quay.io/replicated/docker-packages:rhel-7.4-v1.12.6-${DATE} | tar -t | grep layer.tar | cut -d'/' -f1

export: build
	docker tag quay.io/replicated/docker-packages:rhel-7.4-v1.12.6-${DATE} replicated/docker-packages:rhel-7.4-v1.12.6
	docker save replicated/docker-packages:rhel-7.4-v1.12.6 > packages-docker-rhel74.tar

# this gets run by airgap install script
unpack_example: export
	rm -rf image/
	mkdir -p image/
	tar xvf packages-docker-rhel74.tar -C image
	tar xvf image/a2bf112873793f191c9e2b9cf0fef6fc7a58b93947c9996e8b842ca9b5eaaed4/layer.tar
