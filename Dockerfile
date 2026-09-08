FROM tsl0922/ttyd:latest
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client sed && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 1000 webssh \
    && useradd -u 1000 -g webssh -m -s /bin/bash webssh \
    && mkdir -p /data \
    && chown -R webssh:webssh /data /home/webssh
