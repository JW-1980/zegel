# Zegel CLI Docker image (improvement #102).
#
# Multi-stage build: the first stage pulls the Dart SDK, fetches
# dependencies, and AOT-compiles `cli/bin/zegel.dart` to a single
# self-contained binary. The second stage is a minimal runtime
# (debian:stable-slim) so the resulting image stays under ~100 MB.

FROM dart:stable AS builder
WORKDIR /zegel

# Copy package manifests first so Docker can cache dependencies.
COPY lib/pubspec.yaml lib/pubspec.yaml
COPY cli/pubspec.yaml cli/pubspec.yaml
RUN cd lib && dart pub get && cd ../cli && dart pub get

# Copy the rest and compile.
COPY lib lib
COPY cli cli
RUN cd cli && dart compile exe bin/zegel.dart -o /zegel/bin/zegel

FROM debian:stable-slim AS runtime
LABEL org.opencontainers.image.title="Zegel"
LABEL org.opencontainers.image.description="Tamper-proof file container CLI"
LABEL org.opencontainers.image.source="https://github.com/jw-1980/zegel"
LABEL org.opencontainers.image.licenses="Apache-2.0"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Add a non-root user so the CLI never runs as root by default.
RUN useradd --create-home --shell /usr/sbin/nologin zegel

COPY --from=builder /zegel/bin/zegel /usr/local/bin/zegel
RUN chmod 0755 /usr/local/bin/zegel

USER zegel
WORKDIR /home/zegel

ENTRYPOINT ["/usr/local/bin/zegel"]
CMD ["--help"]
