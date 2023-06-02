FROM golang:1.20 as builder
WORKDIR /docker-compose-generate
COPY ./util/docker-compose-generate /docker-compose-generate
RUN make build


FROM python:2

COPY --from=builder /docker-compose-generate/dcg /dcg
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    shunit2 && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY requirements.txt /usr/src/app/
RUN pip install --no-cache-dir --src /usr/local/src -r requirements.txt

ADD . /usr/src/app

RUN /dcg --raw > /usr/src/app/install_scripts/templates/swarm/docker-compose-generate-safe.sh

ENV ENVIRONMENT dev

EXPOSE 5000

CMD ["python", "main.py"]
