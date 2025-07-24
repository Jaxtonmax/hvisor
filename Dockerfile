# ============== 第一阶段：构建QEMU ==============
FROM ubuntu:22.04 AS qemu-builder
ENV DEBIAN_FRONTEND=noninteractive
ARG QEMU_VERSION=9.0.2
ARG QEMU_INSTALL_PATH=/opt/qemu

# 补充git依赖，解决meson下载dtc.wrap的问题
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # 核心编译工具
    build-essential gcc g++ make \
    # 构建系统依赖（新增git）
    meson ninja-build pkg-config git \  
    # Python工具
    python3 python3-pip python3-venv python3-distutils \
    # 系统库依赖
    libglib2.0-dev libpixman-1-dev libpcre2-dev \
    libslirp-dev libseccomp-dev nettle-dev libgnutls28-dev \
    zlib1g-dev libzstd-dev liblzo2-dev libsnappy-dev \
    libaio-dev libnuma-dev libcapstone-dev \
    # 其他工具
    flex bison wget ca-certificates xz-utils && \
    # 下载并构建QEMU
    wget https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz && \
    tar xJf qemu-${QEMU_VERSION}.tar.xz && \
    cd qemu-${QEMU_VERSION} && \
    ./configure \
        --prefix=${QEMU_INSTALL_PATH} \
        --target-list=aarch64-softmmu,riscv64-softmmu \
        --enable-kvm \
        --enable-slirp \
        --enable-nettle \
        --disable-docs \
        --disable-gtk \
        --disable-vnc \
        --enable-debug && \
    make -j$(nproc) && \
    make install && \
    # 清理残留
    cd .. && \
    rm -rf qemu-${QEMU_VERSION}* && \
    apt-get purge -y --auto-remove && \
    rm -rf /var/lib/apt/lists/*


# ============== 第二阶段：安装工具链 ==============
FROM ubuntu:22.04 AS toolchain-installer
ENV DEBIAN_FRONTEND=noninteractive

# 复制riscv64工具链（替换原riscv32的COPY指令）
COPY riscv64-glibc-ubuntu-22.04-gcc-nightly-2025.07.16-nightly.tar.xz /tmp/
COPY loongarch64-clfs-8.0-cross-tools-gcc-full.tar.xz /tmp/

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget ca-certificates xz-utils && \
    # 安装ARM工具链（保持不变）
    ARM_VERSION=10.3-2021.07 && \
    ARM_INSTALL_PATH=/opt/aarch64-none-linux-gnu && \
    mkdir -p ${ARM_INSTALL_PATH} && \
    wget --show-progress https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu-a/${ARM_VERSION}/binrel/gcc-arm-${ARM_VERSION}-x86_64-aarch64-none-linux-gnu.tar.xz && \
    tar xJf gcc-arm-${ARM_VERSION}-x86_64-aarch64-none-linux-gnu.tar.xz \
        -C ${ARM_INSTALL_PATH} \
        --strip-components=1 && \
    rm gcc-arm-${ARM_VERSION}-x86_64-aarch64-none-linux-gnu.tar.xz && \
    # 安装RISC-V 64位工具链（修改路径和文件名）
    # 在toolchain-installer阶段，将RISCV_VERSION修改为包含末尾的-nightly
    RISCV_VERSION=2025.07.16-nightly && \  
    RISCV_INSTALL_PATH=/opt/riscv64-unknown-linux-gnu && \  
    mkdir -p ${RISCV_INSTALL_PATH} && \
    # 此时变量展开后会匹配COPY的文件名
    cp /tmp/riscv64-glibc-ubuntu-22.04-gcc-nightly-${RISCV_VERSION}.tar.xz . && \
    tar xJf riscv64-glibc-ubuntu-22.04-gcc-nightly-${RISCV_VERSION}.tar.xz \
        -C ${RISCV_INSTALL_PATH} \
        --strip-components=1 && \
    rm riscv64-glibc-ubuntu-22.04-gcc-nightly-${RISCV_VERSION}.tar.xz && \
    # 安装LoongArch工具链（保持不变）
    LOONGARCH_INSTALL_PATH=/opt/loongarch64-unknown-linux-gnu && \
    mkdir -p ${LOONGARCH_INSTALL_PATH} && \
    cp /tmp/loongarch64-clfs-8.0-cross-tools-gcc-full.tar.xz . && \
    tar -xf loongarch64-clfs-8.0-cross-tools-gcc-full.tar.xz \
        -C ${LOONGARCH_INSTALL_PATH} \
        --strip-components=1 && \
    rm loongarch64-clfs-8.0-cross-tools-gcc-full.tar.xz && \
    # 清理缓存
    apt-get purge -y --auto-remove && \
    rm -rf /var/lib/apt/lists/*



# ============== 第三阶段：Rust安装 ==============
FROM ubuntu:22.04 AS rust-installer
ENV DEBIAN_FRONTEND=noninteractive

# 关键：添加build-essential以提供C编译器（cc/gcc）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl ca-certificates \
    build-essential && \  
    # 配置国内Rust镜像（中科大镜像）
    export RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static && \
    export RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup && \
    # 安装Rust（使用镜像源加速）
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal && \
    export PATH="/root/.cargo/bin:${PATH}" && \
    # 配置cargo国内镜像（加速crates下载）
    echo '[source.crates-io]' > /root/.cargo/config && \
    echo 'replace-with = "ustc"' >> /root/.cargo/config && \
    echo '[source.ustc]' >> /root/.cargo/config && \
    echo 'registry = "git://mirrors.ustc.edu.cn/crates.io-index"' >> /root/.cargo/config && \
    # 安装目标平台和组件
    rustup target add \
    aarch64-unknown-none \
    riscv64gc-unknown-none-elf \
    loongarch64-unknown-none && \
    rustup component add rust-src rustfmt && \
    # 安装cargo工具（现在有cc链接器了）
    cargo install --version 0.3.0 --locked cargo-binutils && \
    cargo install cargo-xbuild && \
    # 清理缓存
    apt-get purge -y --auto-remove && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /root/.cargo/registry/*


# ============== 第四阶段：最终镜像 ==============
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 复制工具
COPY --from=qemu-builder /opt/qemu /opt/qemu
COPY --from=toolchain-installer /opt/aarch64-none-linux-gnu /opt/aarch64-none-linux-gnu
COPY --from=toolchain-installer /opt/riscv64-unknown-linux-gnu /opt/riscv64-unknown-linux-gnu
COPY --from=toolchain-installer /opt/loongarch64-unknown-linux-gnu /opt/loongarch64-unknown-linux-gnu
COPY --from=rust-installer /root/.cargo /root/.cargo
COPY --from=rust-installer /root/.rustup /root/.rustup

# 安装系统依赖（添加了libpixman-1-0解决QEMU运行时依赖）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential git gdb-multiarch llvm-dev libclang-dev \
    expect device-tree-compiler p7zip-full gcc-aarch64-linux-gnu \
    gcc-riscv64-linux-gnu curl cmake libssl-dev pkg-config \
    python3 python3-pip \
    libpixman-1-0 \
    libglib2.0-0 \
    libslirp0 \
    libcapstone4 \
    libsnappy1v5 \ 
    liblzo2-2 \              
    libsnappy1v5 \           
    libaio1 \                
    libnuma1 \               
    libcapstone4 && \ 
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 设置环境变量
ENV PATH="/opt/qemu/bin:/opt/aarch64-none-linux-gnu/bin:/opt/riscv64-unknown-linux-gnu/bin:/opt/loongarch64-unknown-linux-gnu/cross-tools/bin:/root/.cargo/bin:${PATH}"
ENV RUSTUP_HOME=/root/.rustup
ENV CARGO_HOME=/root/.cargo

# 验证安装
RUN qemu-system-aarch64 --version && \
    aarch64-none-linux-gnu-gcc --version && \
    riscv64-unknown-linux-gnu-gcc --version && \
    rustc --version && \
    cargo --version

WORKDIR /workspace
CMD ["/bin/bash"]
