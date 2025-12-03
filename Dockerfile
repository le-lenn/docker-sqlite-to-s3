FROM alpine:3.23

ARG TARGETARCH

# Install runtime dependencies and go-cron via a dedicated installer
COPY src/install.sh /usr/src/install.sh
RUN sh /usr/src/install.sh

# Copy the application scripts
COPY src /usr/src

WORKDIR /usr/src
RUN chmod +x /usr/src/*.sh
ENTRYPOINT ["/usr/src/run.sh"]
CMD [""]
