build:
	docker build -t quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3 .
	docker build -t quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3.20180417 .

push:
	docker push quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3
	docker push quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3.20180417

# this gets run by airgap install script
unpack_example:
	rm -rf image/
	mkdir -p image/
	docker save quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3 > image.tar
	tar xvf image.tar -C image
	tar xvf image/f7126e84abc96fbc8495c33052724fad48115829e86987adbf556474f0ead5c1/layer.tar
	
	
