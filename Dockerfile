FROM alpine
RUN \
	apk add --no-cache rsync && \
	rm -rf /var/cache/apk/*

ENTRYPOINT ["/usr/bin/rsync"]
