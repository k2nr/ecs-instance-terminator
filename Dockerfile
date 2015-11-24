FROM alpine:3.2

RUN apk add --update curl jq python docker && \
    curl -O https://bootstrap.pypa.io/get-pip.py && \
    python get-pip.py && \
    pip install awscli && \
    rm -rf /var/cache/apk/*

COPY run.sh /run.sh

CMD ["/run.sh"]
