FROM ubuntu:16.04
RUN apt-get -y update
RUN apt-get -y upgrade
RUN apt-get -y install apt-utils apt-transport-https ca-certificates
RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
RUN echo "deb https://apt.dockerproject.org/repo ubuntu-xenial experimental" > /etc/apt/sources.list.d/docker.list
RUN apt-get -y update
RUN mkdir -p /packages/archives/partial
RUN apt-get -d -y install docker-engine=1.12.3-0~xenial -oDebug::NoLocking=1 -o=dir::cache=/packages/

FROM scratch
COPY --from=0 /packages /
