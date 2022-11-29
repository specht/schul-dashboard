FROM neo4j:4.4-community

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y tzdata && rm -rf /var/cache/apt/*
RUN cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime && echo "Europe/Berlin" > /etc/timezone
USER 1000:1000
