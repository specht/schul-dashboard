FROM nginx:stable
MAINTAINER Dr. Michael Specht <specht@gymnasiumsteglitz.de>

COPY default.conf /etc/nginx/conf.d/

ENV TZ=Europe/Berlin
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
