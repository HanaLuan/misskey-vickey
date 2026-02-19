ARG NODE_VERSION=24

############################
# Stage 1: Build Everything
############################

FROM node:${NODE_VERSION} AS builder

RUN apt-get update && apt-get install -y \
    build-essential curl pkg-config libssl-dev \
    && curl https://sh.rustup.rs -sSf | sh -s -- -y

ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /misskey

# install pnpm
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN node -e "console.log(JSON.parse(require('fs').readFileSync('./package.json')).packageManager)" | xargs npm install -g

# copy minimal first for caching
COPY scripts ./scripts
COPY patches ./patches
COPY packages ./packages
COPY .config/example.yml ./.config/default.yml
COPY . .

RUN git submodule update --init
RUN pnpm install --frozen-lockfile
RUN pnpm build:legacy
RUN rm -rf .git

############################
# Stage 2: Runtime
############################

FROM node:${NODE_VERSION}-trixie

ARG UID=991
ARG GID=991

RUN apt-get update && apt-get install -y \
    ffmpeg tini curl libjemalloc-dev libjemalloc2 \
    && ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so \
    && groupadd -g ${GID} misskey \
    && useradd -m -u ${UID} -g ${GID} misskey

WORKDIR /misskey

COPY --from=builder /misskey /misskey

RUN chown -R misskey:misskey /misskey

RUN node -e "console.log(JSON.parse(require('fs').readFileSync('./package.json')).packageManager)" | xargs npm install -g

USER misskey

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so
ENV NODE_ENV=production

HEALTHCHECK --interval=5s --retries=20 CMD ["/bin/bash", "/misskey/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["pnpm", "run", "migrateandstart"]
