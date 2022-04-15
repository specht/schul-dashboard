FROM ruby:2-alpine
MAINTAINER Dr. Michael Specht <specht@gymnasiumsteglitz.de>

RUN apk update && apk upgrade
RUN apk add libressl-dev cmake alpine-sdk less curl bash curl-dev ruby-dev imagemagick build-base docker libwebp-tools librsvg tzdata inkscape && rm -rf /var/cache/apk/*
RUN wget -O seabolt.zip https://github.com/neo4j-drivers/seabolt/archive/refs/tags/v1.7.4.zip
RUN unzip seabolt.zip
RUN cd seabolt-1.7.4 && ./make_release.sh
RUN cp /seabolt-1.7.4/build/dist/lib/libseabolt17.so /usr/local/lib
RUN cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime && echo "Europe/Berlin" > /etc/timezone
RUN gem install bundler
ADD Gemfile /
RUN bundle install
RUN adduser -D -u 1000 dashboard
USER dashboard
