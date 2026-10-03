FROM ruby:3.4

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get upgrade -y &&\
    apt-get install -y --no-install-recommends\
    chromium chromium-driver chromium-sandbox \
    libglib2.0-0 \
    libnss3 \
    libxss1 \
    libasound2 \
    libatk-bridge2.0-0 \
    libgtk-3-0 \
    libdrm2 \
    curl ca-certificates \
    unzip \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Chromium's hyphenation dictionaries, so that `hyphens: auto` works in the PDFs. Debian's chromium
# ships none and Chrome cannot download them here - see docker/install-hyphen-data.sh for the whole
# story. They go next to the chromium binary, where the component installer looks for a bundled copy.
ARG HYPHEN_DATA_CHROMIUM_REF=refs/tags/154.0.8037.92
COPY ./docker/install-hyphen-data.sh /usr/local/bin/install-hyphen-data.sh
RUN chmod +x /usr/local/bin/install-hyphen-data.sh && \
    /usr/local/bin/install-hyphen-data.sh "${HYPHEN_DATA_CHROMIUM_REF}" /usr/lib/chromium/hyphen-data

# Create a non-root user
RUN groupadd -r appuser && useradd -r -g appuser -m -d /home/appuser appuser

# ARM compatibility workaround:
# On ARM architectures (such as Apple Silicon), downloading chromedriver via automated scripts may fail or cause ELF binary errors,
# such as "rosetta error: failed to open elf at /lib64/ld-linux-x86-64.so.2".
# To avoid these issues, we directly install 'chromium-driver' via the package manager and explicitly create a symlink in the expected location.

RUN mkdir -p /home/appuser/.webdrivers && ln -s /usr/bin/chromedriver /home/appuser/.webdrivers/chromedriver

# Set working directory
WORKDIR /app

# Copy your gem into container
COPY ./pkg/bidi2pdf-*.gem ./

# pdf-reader is deliberately not a bidi2pdf runtime dependency - it is installed here, as its own
# step, so the published image always has `pages`/PDF assertions available, the environment an
# agent or CI job actually renders in.
RUN gem install ./bidi2pdf-*.gem && \
    gem install pdf-reader -v "~> 2.14" && \
    chown -R appuser:appuser /app

# Switch to non-root user
# Chromium's crash handler gets its database path from the XDG config dir. On a read-only root
# (docker run --read-only) that dir cannot be created, the handler refuses to start
# ("--database is required") and Chrome aborts on every launch. /tmp is the one place such a
# container is expected to mount writable (--tmpfs /tmp).
ENV XDG_CONFIG_HOME=/tmp/xdg-config \
    XDG_CACHE_HOME=/tmp/xdg-cache

USER appuser

CMD ["/usr/bin/bash"]