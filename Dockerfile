FROM alpine:3.18

RUN apk add --no-cache git wget libuv-dev
RUN wget https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz

RUN tar -xf zig-linux-x86_64-0.11.0.tar.xz -C /var/tmp
RUN mv /var/tmp/zig-linux-x86_64-0.11.0 /usr/local/zig
RUN ln -s /usr/local/zig/zig /usr/local/bin/zig

COPY . .
WORKDIR .
RUN git submodule init && git submodule update
RUN ./configure
RUN zig build -Doptimize=ReleaseFast --verbose
COPY origin/files/fib.json /var/rinha/source.rinha.json
ENTRYPOINT ["zig-out/bin/touka", "/var/rinha/source.rinha.json"]

