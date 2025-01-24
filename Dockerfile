# 构建带 Brotli 和 HTTP/3 的 Nginx
ARG NGINX_VERSION=1.27.3
FROM nginx:${NGINX_VERSION} AS nginx_builder
ARG NGINX_VERSION

# Nginx 工作目录
WORKDIR /root/

# 安装所需依赖
RUN apt-get update && apt-get install -y \
    wget \
    build-essential \
    git \
    libpcre3-dev \
    libssl-dev \
    zlib1g-dev \
    libbrotli-dev \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 下载 Nginx 源码和 Brotli 模块
RUN wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
    && tar zxf nginx-${NGINX_VERSION}.tar.gz \
    && git clone --recursive https://github.com/google/ngx_brotli.git \
    && cd ngx_brotli && git submodule update --init --recursive && cd ..

# 下载 Cloudflare 的 QUIC/HTTP3 补丁
RUN git clone --recursive https://github.com/cloudflare/quiche.git \
    && cd quiche && git submodule update --init --recursive && cd ..

# 构建带有 Brotli 和 HTTP/3 的 Nginx
RUN cd nginx-${NGINX_VERSION} \
    && patch -p1 < ../quiche/extras/nginx/nginx-1.27.patch \
    && ./configure \
    --add-dynamic-module=../ngx_brotli \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-openssl=../quiche/deps/boringssl \
    --with-quiche=../quiche \
    && make modules

# 构建最终的镜像
FROM nginx:${NGINX_VERSION}-alpine
LABEL maintainer="jiangzhiyan"

ARG NGINX_VERSION

# 复制模块
COPY --from=nginx_builder /root/nginx-${NGINX_VERSION}/objs/ngx_http_brotli_filter_module.so /usr/lib/nginx/modules/
COPY --from=nginx_builder /root/nginx-${NGINX_VERSION}/objs/ngx_http_brotli_static_module.so /usr/lib/nginx/modules/
COPY --from=nginx_builder /root/nginx-${NGINX_VERSION}/objs/ngx_http_v3_module.so /usr/lib/nginx/modules/

# 复制配置文件
COPY nginx.template.conf /etc/nginx/nginx.conf

# 设置时区
ENV TZ=Asia/Shanghai

# 暴露 HTTP/3 和 HTTP/2 端口
EXPOSE 80 443 443/udp

# 启动 Nginx
CMD ["/bin/sh", "-c", "nginx -g 'daemon off;'"]
