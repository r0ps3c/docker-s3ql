FROM alpine AS build

ENV PYTHONUNBUFFERED 1
ARG S3QL_VERSION="3.5.1"
ARG FILE="s3ql-$S3QL_VERSION"
ARG URL="https://github.com/s3ql/s3ql/releases/download/release-$S3QL_VERSION/$FILE.tar.bz2"
ARG PIPS="cryptography defusedxml requests apsw>=3.7.0 trio>=0.9 pyfuse3>=3.0,<4.0 dugong>=3.4,<4.0 google-auth google-auth-oauthlib wheel"

RUN \
	apk --no-cache add curl gnupg jq bzip2 g++ make pkgconfig fuse3-dev sqlite-dev libffi-dev openssl-dev python3-dev py3-pip
RUN \
	pip3 install --user --ignore-installed $PIPS

RUN gpg2 --batch --keyserver keys.gnupg.net --recv-key 0xD113FCAC3C4E599F

RUN \
	set -x; \
    	curl -sfL "$URL" -o "/tmp/$FILE.tar.bz2" && \
 	curl -sfL "$URL.asc" | gpg2 --batch --verify - "/tmp/$FILE.tar.bz2" && \
 	tar -xjf "/tmp/$FILE.tar.bz2"

WORKDIR $FILE
RUN \
	pip wheel -w /tmp/wheels .

FROM alpine
RUN apk --no-cache add fuse3 psmisc py3-pip
COPY --from=build /tmp/wheels /tmp/wheels
RUN \
	pip install --find-links /tmp/wheels s3ql && \
	rm -rf /var/cache/apk/* /tmp/wheels

COPY entrypoint /
ENTRYPOINT ["/entrypoint"]
