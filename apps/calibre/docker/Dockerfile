FROM ubuntu:24.04

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    python3 \
    python3-pip \
    wget \
    xz-utils \
    xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Calibre
# Using the official installer to get latest calibre with calibredb CLI
RUN wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | sh /dev/stdin install_dir=/opt/calibre

# Add calibre to PATH
ENV PATH="/opt/calibre:${PATH}"

# Copy puller script
COPY puller.sh /usr/local/bin/puller.sh
RUN chmod +x /usr/local/bin/puller.sh

# Create default library directory
RUN mkdir -p /data/calibre-library

# Run as non-root user
RUN useradd -m -u 1000 calibre && \
    chown -R calibre:calibre /data/calibre-library
USER calibre

WORKDIR /data

ENTRYPOINT ["/usr/local/bin/puller.sh"]
