FROM jenkins/inbound-agent:latest

USER root

RUN apt-get update \
    && apt-get install -y \
        nodejs \
        npm \
        docker.io \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY start-agent.sh /usr/local/bin/start-agent.sh
RUN chmod +x /usr/local/bin/start-agent.sh

ENTRYPOINT ["/usr/local/bin/start-agent.sh"]