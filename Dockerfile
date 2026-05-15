# Stage 1: grab docker CLI + compose plugin
FROM docker:25-cli AS docker-stage

# Stage 2: runtime
FROM node:18-alpine
COPY --from=docker-stage /usr/local/bin/docker                        /usr/local/bin/docker
COPY --from=docker-stage /usr/local/libexec/docker/cli-plugins        /usr/local/libexec/docker/cli-plugins

WORKDIR /app
# Files are volume-mounted from the host repo at runtime (./:/app in compose).
# These copies are fallbacks for standalone image use.
COPY bin/    ./bin/
COPY src/    ./src/
COPY public/ ./public/

EXPOSE 7979
CMD ["node", "bin/setup.js"]
