ARG DEBIAN_CODENAME=trixie

FROM debian:${DEBIAN_CODENAME}-slim

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:0 \
    XDG_RUNTIME_DIR=/tmp/xdg

ARG TARGETARCH
ARG USE_RPI_CHROMIUM=auto
ARG DEBIAN_CODENAME

COPY bin/install.sh /usr/src/install.sh
RUN chmod a+x /usr/src/install.sh && \
    TARGETARCH="${TARGETARCH}" USE_RPI_CHROMIUM="${USE_RPI_CHROMIUM}" /usr/src/install.sh

COPY bin/run.sh /usr/local/bin/run.sh
RUN chmod a+x /usr/local/bin/run.sh

CMD ["/usr/bin/dumb-init","--","/usr/local/bin/run.sh"]
