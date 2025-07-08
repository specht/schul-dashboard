FROM ruby:3-alpine

RUN apk update && apk upgrade
RUN apk add less curl bash curl-dev ruby-dev imagemagick build-base docker libreoffice openjdk11-jre libwebp-tools msttcorefonts-installer librsvg tzdata inkscape graphviz ffmpeg zip poppler-utils ghostscript && rm -rf /var/cache/apk/*
RUN update-ms-fonts
RUN fc-cache -f
RUN cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime && echo "Europe/Berlin" > /etc/timezone
RUN gem install bundler
ADD Gemfile /
RUN bundle install
RUN adduser -D -u 1000 dashboard
USER dashboard
