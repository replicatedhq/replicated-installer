DATE=$(shell date +%Y%m%d)

build:
	docker build -t quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3-${DATE} .

push:
	docker push quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3-${DATE}

print_layer_id:
	@docker save quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3-${DATE} | tar -t | grep layer.tar | cut -d'/' -f1

# this gets run by airgap install script
unpack_example:
	rm -rf image/
	mkdir -p image/
	docker save quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3-${DATE} > image.tar
	tar xvf image.tar -C image
	tar xvf image/9d11016cacbae72f929fb839a5ac9c6810f3f9c639a5f140f86792ec4dcb6ceb/layer.tar
