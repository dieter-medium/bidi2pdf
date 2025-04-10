FROM ruby:3.3-slim-bookworm

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
    chromium \
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


# Set working directory
WORKDIR /app

# Copy your gem into container
COPY ./pkg/bidi2pdf-*.gem ./

RUN gem install ./bidi2pdf-*.gem && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

CMD ["/usr/bin/bash"]