DATE=$(shell date +%Y%m%d)

build:
	docker build -t quay.io/replicated/docker-packages:ubuntu-1604-v18.06.2-${DATE} .

push:
	docker push quay.io/replicated/docker-packages:ubuntu-1604-v18.06.2-${DATE}

print_layer_id:
	@docker save quay.io/replicated/docker-packages:ubuntu-1604-v18.06.2-${DATE} | tar -t | grep layer.tar | cut -d'/' -f1

# this gets run by airgap install script
unpack_example:
	rm -rf image/
	mkdir -p image/
	docker save quay.io/replicated/docker-packages:ubuntu-1604-v18.06.2-${DATE} > image.tar
	tar xvf image.tar -C image
	tar xvf image/144c540d6db1290e32ccf0c38e3b7b982d8f4ccf66961f122f5cd54fdd255570/layer.tar
