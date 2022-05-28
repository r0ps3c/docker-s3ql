ARG S3QL_VERSION="3.8.1"
ARG S3QL_FILE="s3ql-${S3QL_VERSION}.tar.gz"
ARG S3QL_URL="https://github.com/r0ps3c/s3ql/releases/download/release-${S3QL_VERSION}-mpc.1/${S3QL_FILE}"
ARG PYFUSE3_VERSION="3.2.1"
ARG PYFUSE3_FILE="pyfuse3-${PYFUSE3_VERSION}.tar.gz"
ARG PYFUSE3_URL="https://github.com/r0ps3c/pyfuse3/releases/download/release-${PYFUSE3_VERSION}/${PYFUSE3_FILE}"
ARG S3QL_BUILD_PIPS="cryptography defusedxml requests apsw>=3.7.0 trio>=0.15 dugong>=3.4,<4.0 google-auth google-auth-oauthlib wheel sphinx"

FROM alpine AS build

ENV PYTHONUNBUFFERED 1
ARG S3QL_BUILD_PIPS
ARG S3QL_URL
ARG S3QL_FILE
ARG S3QL_VERSION
ARG PYFUSE3_URL
ARG PYFUSE3_FILE
ARG PYFUSE3_VERSION

RUN \
	apk --no-cache add curl gnupg jq bzip2 g++ make pkgconfig fuse3-dev sqlite-dev libffi-dev openssl-dev python3-dev py3-pip rust cargo cython texlive texmf-dist-latexextra bash
RUN \
	pip install --user --ignore-installed ${S3QL_BUILD_PIPS}

RUN \
    	curl -sfL "${PYFUSE3_URL}" -o "/tmp/${PYFUSE3_FILE}" && \
 	tar -xf "/tmp/${PYFUSE3_FILE}" && \
	cd pyfuse3-${PYFUSE3_VERSION} && \
	pip wheel -w /tmp/pyfusewheels .

# install pyfuse3 wheel that we built, and also copy it to the wheel
# dir as building s3ql wheels will overwrite anything in the destination
# with the (broken) version from pypi
RUN \
	pip install --find-links /tmp/pyfusewheels pyfuse3 && \ 
    	curl -sfL "$S3QL_URL" -o "/tmp/$S3QL_FILE" && \
 	tar -xf "/tmp/$S3QL_FILE" && \
	cd s3ql-$S3QL_VERSION && \
	pip wheel -w /tmp/wheels . && \
	mv /tmp/pyfusewheels/pyfuse*.whl /tmp/wheels

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
