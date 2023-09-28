FROM rust:1.72-bookworm

WORKDIR /usr/src/touka

COPY . .

RUN cargo build --release

CMD ["bash", "-c", "\"/usr/src/touka/target/release/touka /var/rinha/source.rinha\" && tcc -run output.c"]