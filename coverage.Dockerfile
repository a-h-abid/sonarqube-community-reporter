FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG KCOV_VERSION=v43

RUN set -eux; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends \
      bats \
      jq \
      parallel \
      git \
      ca-certificates \
      build-essential \
      cmake \
      binutils-dev \
      libcurl4 \
      libcurl4-openssl-dev \
      libdw1 \
      libdw-dev \
      libelf1 \
      libelf-dev \
      libbinutils \
      libiberty-dev \
      zlib1g-dev \
      libssl-dev \
      libstdc++-12-dev; \
    tmpdir="$(mktemp -d)"; \
    git clone --depth 1 --branch "${KCOV_VERSION}" \
      https://github.com/SimonKagstrom/kcov.git "${tmpdir}/kcov"; \
    cmake -S "${tmpdir}/kcov" -B "${tmpdir}/build" \
      -DCMAKE_INSTALL_PREFIX="/usr/local"; \
    cmake --build "${tmpdir}/build" --parallel "$(nproc)"; \
    cmake --install "${tmpdir}/build"; \
    apt-get clean; rm -rf "${tmpdir}" /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    bats --version; \
    jq --version; \
    kcov --version

WORKDIR /workspace
