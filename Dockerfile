ARG S3QL_VERSION="5.2.3+rp1"
ARG S3QL_FILE="s3ql-${S3QL_VERSION}.tar.gz"
ARG S3QL_URL="https://github.com/r0ps3c/s3ql/releases/download/release-${S3QL_VERSION}/${S3QL_FILE}"
ARG S3QL_BUILD_PIPS="wheel cryptography defusedxml requests apsw>=3.7.0 trio>=0.15 google-auth google-auth-oauthlib sphinx pyfuse3>=3.2.2 setuptools"

FROM alpine AS build

ENV PYTHONUNBUFFERED=1
ARG S3QL_BUILD_PIPS
ARG S3QL_URL
ARG S3QL_FILE
ARG S3QL_VERSION
ARG PYFUSE3_URL
ARG PYFUSE3_FILE
ARG PYFUSE3_VERSION

RUN \
	apk --no-cache add curl gnupg jq bzip2 g++ make pkgconfig fuse3-dev sqlite-dev libffi-dev openssl-dev python3-dev py3-pip rust cargo cython texlive texmf-dist-latexextra bash git
RUN \
	python3 -m venv s3ql-build && \
	source ./s3ql-build/bin/activate && \
	pip install --ignore-installed ${S3QL_BUILD_PIPS} && \
   	curl -sfL "$S3QL_URL" -o "/tmp/$S3QL_FILE" && \
 	tar -xf "/tmp/$S3QL_FILE" && \
	cd s3ql-$S3QL_VERSION && \
	pip wheel -w /tmp/wheels .

FROM alpine
ARG S3QL_VERSION
RUN apk --no-cache add fuse3 psmisc py3-pip bash findutils attr moreutils
COPY --from=build /tmp/wheels /tmp/wheels
RUN \
	pip install --break-system-packages --find-links /tmp/wheels s3ql && \
	rm -rf /var/cache/apk/* /tmp/wheels

COPY --from=build s3ql-$S3QL_VERSION/contrib/expire_backups.py /usr/local/bin/expire_backups.py
COPY entrypoint /
ENTRYPOINT ["/entrypoint"]
