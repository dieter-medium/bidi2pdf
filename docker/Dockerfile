FROM ruby:3.3

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get upgrade -y &&\
    apt-get install -y --no-install-recommends\
    chromium chromium-driver\
    libglib2.0-0 \
    libnss3 \
    libxss1 \
    libasound2 \
    libatk-bridge2.0-0 \
    libgtk-3-0 \
    libdrm2 \
    curl \
    unzip \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

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

RUN gem install ./bidi2pdf-*.gem && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

CMD ["/usr/bin/bash"]