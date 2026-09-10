# Tycoon 专用服务器（Linux 无头导出产物）
# 使用：先在 Godot 编辑器导出 "Linux Server" 预设（见 deploy/README.md），
# 把产物 tycoon_server.x86_64 放到本目录，然后 docker compose up -d --build
FROM debian:bookworm-slim

WORKDIR /app
COPY tycoon_server.x86_64 /app/tycoon_server.x86_64
RUN chmod +x /app/tycoon_server.x86_64 && \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

EXPOSE 24565/udp

# AppMode 解析 --server / --port；AI 节奏默认值见 src/autoload/app_mode.gd
CMD ["/app/tycoon_server.x86_64", "--server", "--port", "24565"]
