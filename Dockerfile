FROM tsl0922/ttyd:latest
ENV LANG=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client && rm -rf /var/lib/apt/lists/*
