FROM python:2.7

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    shunit2 && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY requirements.txt /usr/src/app/
RUN pip install --no-cache-dir --src /usr/local/src -r requirements.txt

COPY . /usr/src/app

CMD ["python", "app/app.py"]
