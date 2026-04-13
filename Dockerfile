# Zegel CLI & Library Docker image
# Multi-stage build for minimal image size

FROM dart:stable AS builder

WORKDIR /app

# Copy library package
COPY lib/ lib/

# Copy CLI package
COPY cli/ cli/

# Install dependencies
RUN cd lib && dart pub get
RUN cd cli && dart pub get

# Compile CLI to native executable
RUN cd cli && dart compile exe bin/zegel.dart -o /app/zegel

# Runtime stage - minimal image
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/zegel /usr/local/bin/zegel

# Non-root user for security
RUN useradd -m -s /bin/bash zegel
USER zegel
WORKDIR /home/zegel

ENTRYPOINT ["zegel"]
CMD ["--help"]
