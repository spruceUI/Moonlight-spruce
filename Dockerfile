FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Configure multiarch for arm64 cross-compilation (glibc 2.31)
RUN dpkg --add-architecture arm64 && \
    sed -i 's/^deb http/deb [arch=amd64] http/g' /etc/apt/sources.list && \
    echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    pkg-config \
    git \
    ca-certificates \
    wget \
    ccache \
    # arm64 cross-compile dependencies
    libsdl2-dev:arm64 \
    libasound2-dev:arm64 \
    libopus-dev:arm64 \
    libevdev-dev:arm64 \
    libpulse-dev:arm64 \
    libavahi-client-dev:arm64 \
    libudev-dev:arm64 \
    libexpat1-dev:arm64 \
    uuid-dev:arm64 \
    libavcodec-dev:arm64 \
    libavutil-dev:arm64 \
    libvpx-dev:arm64 \
    libx264-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

COPY build.sh /build.sh
RUN chmod +x /build.sh
COPY patches/ /patches/

WORKDIR /build
ENTRYPOINT ["/build.sh"]
