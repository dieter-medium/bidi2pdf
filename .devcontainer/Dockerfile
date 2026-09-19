FROM mcr.microsoft.com/devcontainers/ruby:2-3.4-trixie

# Install Rails
RUN su vscode -c "/usr/local/rvm/bin/rvm fix-permissions"

RUN rm -f /etc/apt/sources.list.d/yarn.list \
    && find /etc/apt/sources.list.d -type f \
       -exec sed -i '\|https://dl.yarnpkg.com/debian|d' {} + \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
       git \
       nodejs \
       ca-certificates \
       curl \
       openssh-server \
       procps \
       util-linux \
       socat \
       libjemalloc2 libvips sqlite3 libyaml-dev chromium-driver \
    && rm -rf /var/lib/apt/lists/*

# Default value to allow debug server to serve content over GitHub Codespace's port forwarding service
# The value is a comma-separated list of allowed domains 
ENV RAILS_DEVELOPMENT_HOSTS=".githubpreview.dev,.preview.app.github.dev,.app.github.dev"

# Install rbenv and ruby-build as vscode.
RUN su  vscode -c 'curl -fsSL https://rbenv.org/install.sh | bash'

# Install and select Ruby 3.4.8.
RUN su vscode -c '\
    export RBENV_ROOT="$HOME/.rbenv" && \
    export PATH="$RBENV_ROOT/bin:$PATH" && \
    eval "$(rbenv init - bash)" && \
    rbenv install 3.4.8 && \
    rbenv global 3.4.8 && \
    rbenv rehash && \
    ruby --version \
'

RUN mkdir -p /home/vscode/.webdrivers \
    && chown -R vscode:vscode /home/vscode/.webdrivers \
    && ln -sfn /usr/bin/chromedriver /home/vscode/.webdrivers/chromedriver \

# [Optional] Uncomment this section to install additional OS packages.
# RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends <your-package-list-here>

# [Optional] Uncomment this line to install additional gems.
# RUN su vscode -c "gem install <your-gem-names-here>"

# [Optional] Uncomment this line to install global node packages.
# RUN su vscode -c "source /usr/local/share/nvm/nvm.sh && npm install -g <your-package-here>" 2>&1
