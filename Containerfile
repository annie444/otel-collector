FROM registry.fedoraproject.org/fedora-minimal:latest AS build

RUN dnf update -y && \
  dnf install -y \
  git \
  make \
  gcc \
  golang \
  findutils \
  && dnf clean all

ARG USER_UID=1001
ARG USER_GID=1001
ENV USER_UID=${USER_UID}
ENV USER_GID=${USER_GID}

RUN groupadd -r -g ${USER_GID} otel
RUN useradd -rm -d /home/otel -s /bin/bash -g otel -u ${USER_UID} otel

USER otel

WORKDIR /home/otel

COPY otelcol-builder.yaml otelcol-builder.yaml
RUN --mount=type=cache,id=gocache,target=/home/otel/.cache,uid=${USER_UID},gid=${USER_GID},mode=0755 \
  export XDG_CACHE_HOME=/home/otel/.cache && \
  export CGO_ENABLED=0 && \
  go install go.opentelemetry.io/collector/cmd/builder@latest && \
  export PATH=$HOME/go/bin:$PATH && \
  builder --verbose --config=otelcol-builder.yaml

FROM registry.fedoraproject.org/fedora-minimal:latest

RUN groupadd -r -g ${USER_GID} otel
RUN useradd -rm -d /home/otel -s /bin/bash -g otel -u ${USER_UID} otel

USER otel

WORKDIR /home/otel

COPY --from=build --chmod=0755 /home/otel/bin/otelcol /home/otel/bin/otelcol

ENTRYPOINT ["/home/otel/bin/otelcol"]

CMD ["--config", "/etc/otelcol/config.yaml"]

EXPOSE 4317/tcp
EXPOSE 4318/tcp
EXPOSE 55678/tcp
EXPOSE 55679/tcp
