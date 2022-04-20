FROM alpine

WORKDIR /srv

RUN \
# Create user
    addgroup -g 427 -S cloudflare \
    && adduser -u 427 -S cloudflare -G cloudflare \
# Install programs
    && apk add --no-cache bash curl jq \
# Cleanup
    && rm -rf /tmp/* /var/cache/apk/*

COPY cloudflare-update.sh /srv

USER cloudflare
ENTRYPOINT ["/bin/bash", "cloudflare-update.sh"]
