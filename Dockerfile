# =========================================================================
# 阶段 1: QEMU 构建器
# =========================================================================
FROM ubuntu:22.04 AS qemu-builder

# 1. 安装编译 QEMU 所需的所有依赖项
# 【关键修复】根据您的成功范例，移除了 python3-pip 和所有 pip install 命令。
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    build-essential \
    wget \
    ninja-build \
    pkg-config \
    git \
    python3 \
    python3-venv \
    libglib2.0-dev \
    libfdt-dev \
    libpixman-1-dev \
    zlib1g-dev \
    libslirp-dev \
    nettle-dev \
    meson \
    flex \
    bison && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 2. 下载并解压 QEMU 源码
WORKDIR /build
ARG QEMU_VERSION=9.0.2
RUN wget "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz" && \
    tar -xf "qemu-${QEMU_VERSION}.tar.xz"

# 3. 配置、编译和安装 QEMU
# 使用了 action.yml 中更详细的配置参数，以确保功能完整性。
WORKDIR /build/qemu-${QEMU_VERSION}
RUN ./configure \
      --prefix=/install \
      --target-list=aarch64-softmmu,riscv64-softmmu,riscv64-linux-user \
      --enable-kvm \
      --enable-nettle \
      --enable-user \
      --enable-linux-user \
      --enable-slirp \
      --enable-debug && \
    make -j$(nproc) && \
    make install

# <<< 第一阶段到此结束 >>>

# =========================================================================
# 阶段 2: 最终的 CI 镜像
# =========================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. 安装运行时依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    build-essential \
    git \
    sudo \
    unzip \
    wget \
    curl \
    expect \
    p7zip-full \
    u-boot-tools \
    device-tree-compiler \
    gdb-multiarch \
    llvm-dev \
    libclang-dev \
    gcc-aarch64-linux-gnu \
    gcc-riscv64-linux-gnu \
    libglib2.0-0 \
    libfdt1 \
    libpixman-1-0 \
    libslirp0

# 2. 复制 QEMU
COPY --from=qemu-builder /install /usr/local

# 3. 设置环境变量并安装 Rust
ENV RUSTUP_DIST_SERVER="https://mirrors.ustc.edu.cn/rust-static" \
    RUSTUP_UPDATE_ROOT="https://mirrors.ustc.edu.cn/rust-static/rustup" \
    PATH="/root/.cargo/bin:/usr/local/bin:/opt/aarch64-none-linux-gnu/bin:/opt/riscv64-unknown-linux-gnu/bin:/opt/loongarch-clfs-8.0/cross-tools/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain nightly-2024-05-05 && \
    mkdir -p /root/.cargo && \
    echo '[source.crates-io]' > /root/.cargo/config.toml && \
    echo 'replace-with = "ustc"' >> /root/.cargo/config.toml && \
    echo '' >> /root/.cargo/config.toml && \
    echo '[source.ustc]' >> /root/.cargo/config.toml && \
    echo 'registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"' >> /root/.cargo/config.toml

# 4. 安装 Rust 工具
RUN rustup target add aarch64-unknown-none riscv64gc-unknown-none-elf loongarch64-unknown-none && \
    rustup component add rust-src rustfmt && \
    cargo install --version 0.3.0 --locked cargo-binutils && \
    cargo install --locked cargo-xbuild

# 5. 安装交叉编译工具链
RUN mkdir -p /opt/aarch64-none-linux-gnu /opt/riscv64-unknown-linux-gnu /opt/loongarch-clfs-8.0

COPY toolchains/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz /tmp/
RUN tar xJf /tmp/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz -C /opt/aarch64-none-linux-gnu --strip-components=1

COPY toolchains/riscv64-glibc-ubuntu-22.04-gcc-nightly-2025.06.07-nightly.tar.xz /tmp/
RUN tar xJf /tmp/riscv64-glibc-ubuntu-22.04-gcc-nightly-2025.06.07-nightly.tar.xz -C /opt/riscv64-unknown-linux-gnu --strip-components=1

COPY toolchains/loongarch64-clfs-8.0-cross-tools-gcc-full.tar.xz /tmp/
RUN tar xf /tmp/loongarch64-clfs-8.0-cross-tools-gcc-full.tar.xz -C /opt/loongarch-clfs-8.0

# 6. 清理工作
RUN rm -rf /tmp/* && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 7. 设置工作目录
WORKDIR /workdir