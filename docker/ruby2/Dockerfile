FROM ruby:2-alpine
# EXTRA RUBY CONTAINER FOR share-nc-folders.rb (the nextcloud Gem breaks with Ruby 3)

RUN apk update && apk upgrade
RUN apk add less curl curl-dev bash ruby-dev build-base tzdata && rm -rf /var/cache/apk/*
RUN cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime && echo "Europe/Berlin" > /etc/timezone
RUN gem install bundler -v 2.4.22
ADD Gemfile /
RUN bundle install
RUN adduser -D -u 1000 dashboard
USER dashboard
CMD ["/bin/true"]