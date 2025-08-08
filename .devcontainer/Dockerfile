FROM mcr.microsoft.com/devcontainers/ruby:3.4

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    build-essential \
    libpq-dev \
    postgresql-client \
    pkg-config \
    libssl-dev \
    zlib1g-dev \
    libreadline-dev \
    git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN id -u vscode >/dev/null 2>&1 || ( \
      groupadd --gid 1000 vscode && \
      useradd  --uid 1000 --gid 1000 --shell /bin/bash --create-home vscode )

RUN echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode \
 && chmod 0440 /etc/sudoers.d/vscode

WORKDIR /workspaces/app
USER vscode
CMD ["sleep", "infinity"]

