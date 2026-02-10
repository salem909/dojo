FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    openssh-server \
    ca-certificates \
    curl \
    file \
    python3 \
    bash \
    coreutils \
    grep \
    sed \
    gawk \
    xxd \
    strace \
    ltrace \
    binutils \
    gcc \
    make \
    tini \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash ctf

RUN mkdir -p /run/sshd /home/ctf/.ssh /challenge

COPY sshd_config /etc/ssh/sshd_config
COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

EXPOSE 2222
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/start.sh"]
