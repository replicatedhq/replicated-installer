DATE=$(shell date +%Y%m%d)

build:
	docker build -t quay.io/replicated/docker-packages:ubuntu-1604-v17.09.1-${DATE} .

push:
	docker push quay.io/replicated/docker-packages:ubuntu-1604-v17.09.1-${DATE}

print_layer_id:
	@docker save quay.io/replicated/docker-packages:ubuntu-1604-v17.09.1-${DATE} | tar -t | grep layer.tar | cut -d'/' -f1

# this gets run by airgap install script
unpack_example:
	rm -rf image/
	mkdir -p image/
	docker save quay.io/replicated/docker-packages:ubuntu-1604-v17.09.1-${DATE} > image.tar
	tar xvf image.tar -C image
	tar xvf image/453a2e1be75572b354cf2f6313be490a21cdac745ae4160da5751bd498067b43/layer.tar
