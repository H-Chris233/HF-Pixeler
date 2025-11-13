ARG BASE_IMAGE=eclipse-temurin:21-jre
FROM ${BASE_IMAGE}

ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

ARG EXTRA_DEB_PACKAGES=""
ARG EXTRA_DNF_PACKAGES=""
ARG EXTRA_ALPINE_PACKAGES=""
ARG FORCE_INSTALL_PACKAGES=1

# ✅ 使用 COPY 替代 mount，解决云端权限问题
COPY build/ /build/

RUN chmod -R +x /build && \
    TARGET=${TARGETARCH}${TARGETVARIANT} \
    /build/run.sh install-packages

COPY --from=tianon/gosu /gosu /usr/local/bin/

# ✅ 同样处理第二个 RUN
COPY build/ /build/

RUN chmod -R +x /build && \
    /build/run.sh setup-user

EXPOSE 25565
ARG APPS_REV=1
ARG GITHUB_BASEURL=https://github.com

# ✅ 从本地复制 easy-add
COPY tools/easy-add /usr/bin/easy-add
RUN chmod +x /usr/bin/easy-add

# ✅ 从本地复制 restify
COPY tools/restify /usr/local/bin/restify
RUN chmod +x /usr/local/bin/restify

# ✅ 从本地复制 rcon-cli
COPY tools/rcon-cli /usr/local/bin/rcon-cli
RUN chmod +x /usr/local/bin/rcon-cli

# ✅ 从本地复制 mc-monitor
COPY tools/mc-monitor /usr/local/bin/mc-monitor
RUN chmod +x /usr/local/bin/mc-monitor

# ✅ 从本地复制 mc-server-runner
COPY tools/mc-server-runner /usr/local/bin/mc-server-runner
RUN chmod +x /usr/local/bin/mc-server-runner

ARG MC_HELPER_VERSION=1.50.4
ARG MC_HELPER_BASE_URL=${GITHUB_BASEURL}/itzg/mc-image-helper/releases/download/${MC_HELPER_VERSION}
ARG MC_HELPER_REV=1

# ✅ 从本地复制 mc-image-helper
COPY tools/mc-image-helper-${MC_HELPER_VERSION}.tgz /tmp/
RUN tar -xzf /tmp/mc-image-helper-${MC_HELPER_VERSION}.tgz -C /usr/share/ && \
    ln -s /usr/share/mc-image-helper-${MC_HELPER_VERSION}/ /usr/share/mc-image-helper && \
    ln -s /usr/share/mc-image-helper/bin/mc-image-helper /usr/bin && \
    rm /tmp/mc-image-helper-${MC_HELPER_VERSION}.tgz

VOLUME ["/data"]
WORKDIR /data

STOPSIGNAL SIGTERM

ENV TYPE=VANILLA VERSION=LATEST EULA="" UID=1000 GID=1000 LC_ALL=en_US.UTF-8

COPY --chmod=755 scripts/start* /image/scripts/

COPY --chmod=755 <<EOF /start
#!/bin/bash
exec /image/scripts/start
EOF

COPY --chmod=755 scripts/auto/* /image/scripts/auto/
COPY --chmod=755 scripts/shims/* /image/scripts/shims/
RUN ln -s /image/scripts/shims/* /usr/local/bin/
COPY --chmod=755 files/* /image/

# ✅ 从本地复制 Log4jPatcher
COPY tools/Log4jPatcher.jar /image/Log4jPatcher.jar

RUN dos2unix /image/scripts/start* /image/scripts/auto/*

# ✅ 从本地复制 cloudflared
COPY tools/cloudflared.deb /tmp/cloudflared.deb
RUN dpkg -i /tmp/cloudflared.deb && \
    rm /tmp/cloudflared.deb

# ✅ 安装 Python3 和 pip（不安装 Flask）
RUN apt-get update && \
    apt-get install -y python3 python3-pip net-tools procps && \
    rm -rf /var/lib/apt/lists/*

# ✅ 复制前端和 API 文件
COPY frontend/ /tmp/hf/
COPY api/server.py /tmp/hf/api/

# ✅ 复制多进程启动脚本
COPY --chmod=755 scripts/start-with-tunnel.sh /start-with-tunnel

# ✅ Hugging Face 环境变量（必须在 Dockerfile 中声明）
ENV HF_PORT=7860
ENV HF_HOST=0.0.0.0
ENV TUNNEL_MODE=token
ENV TUNNEL_URL=tcp://localhost:25565

# ✅ 移除 ENTRYPOINT，只使用 CMD（解决冲突）
# ENTRYPOINT [ "/image/scripts/start" ]  # ❌ 删除这一行

# ✅ 使用 exec 形式确保进程替换
CMD ["/bin/bash", "-c", "exec /start-with-tunnel"]

ARG BUILDTIME=local
ARG VERSION=local
ARG REVISION=local
COPY <<EOF /etc/image.properties
buildtime=${BUILDTIME}
version=${VERSION}
revision=${REVISION}
EOF