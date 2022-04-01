ARG S3QL_VERSION="3.8.1"
ARG FILE="s3ql-$S3QL_VERSION.tar.gz"
ARG URL="https://github.com/s3ql/s3ql/releases/download/release-$S3QL_VERSION/$FILE"
ARG PIPS="cryptography defusedxml requests apsw>=3.7.0 trio>=0.9 pyfuse3>=3.0,<4.0 dugong>=3.4,<4.0 google-auth google-auth-oauthlib wheel sphinx"

FROM alpine AS build

ENV PYTHONUNBUFFERED 1
ARG PIPS
ARG URL
ARG FILE
ARG S3QL_VERSION

RUN \
	apk --no-cache add curl gnupg jq bzip2 g++ make pkgconfig fuse3-dev sqlite-dev libffi-dev openssl-dev python3-dev py3-pip rust cargo cython texlive texmf-dist-latexextra bash
RUN \
	pip3 install --user --ignore-installed $PIPS

RUN gpg2 --batch --keyserver keyserver.ubuntu.com --recv-key 0xD113FCAC3C4E599F

RUN \
    	curl -sfL "$URL" -o "/tmp/$FILE" && \
 	curl -sfL "$URL.asc" | gpg2 --batch --verify - "/tmp/$FILE" && \
 	tar -xf "/tmp/$FILE" && \
	cd s3ql-$S3QL_VERSION && \
	pip wheel -w /tmp/wheels .

FROM alpine
ARG S3QL_VERSION
RUN apk --no-cache add fuse3 psmisc py3-pip bash
COPY --from=build /tmp/wheels /tmp/wheels
RUN \
	pip install --find-links /tmp/wheels s3ql && \
	rm -rf /var/cache/apk/* /tmp/wheels

COPY --from=build s3ql-$S3QL_VERSION/contrib/expire_backups.py /usr/local/bin/expire_backups.py
COPY entrypoint /
ENTRYPOINT ["/entrypoint"]
