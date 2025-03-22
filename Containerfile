FROM registry.fedoraproject.org/fedora-minimal:latest

ARG USER_UID=1001
ARG USER_GID=1001
ENV USER_UID=${USER_UID}
ENV USER_GID=${USER_GID}

RUN groupadd -r -g ${USER_GID} otel
RUN useradd -rm -d /home/otel -s /bin/bash -g otel -u ${USER_UID} otel

USER otel

WORKDIR /home/otel

COPY --chmod=0755 otelcol /home/otel/bin/otelcol

ENTRYPOINT ["/home/otel/bin/otelcol"]

CMD ["--config", "/etc/otelcol/config.yaml"]

EXPOSE 4317/tcp
EXPOSE 4318/tcp
EXPOSE 55678/tcp
EXPOSE 55679/tcp
