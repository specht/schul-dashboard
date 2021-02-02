#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require 'yaml'
require './env.rb'

# to get development mode, add the following to your ~/.bashrc:
# export SCHUL_DASHBOARD_DEVELOPMENT=1

DEVELOPMENT = !(ENV['SCHUL_DASHBOARD_DEVELOPMENT'].nil?)

PROJECT_NAME = 'schuldashboard' + (DEVELOPMENT ? 'dev' : '')
DEV_NGINX_PORT = DEVELOPMENT ? 8025 : 8020
DEV_NEO4J_PORT = 8021
LOGS_PATH = DEVELOPMENT ? './logs' : (RUNNING_IN_PRODUCTION ? "/www/logs/#{PROJECT_NAME}" : "/home/qts/logs/#{PROJECT_NAME}")
DATA_PATH = DEVELOPMENT ? './data' : (RUNNING_IN_PRODUCTION ? "/www/data/#{PROJECT_NAME}" : "/home/qts/data/#{PROJECT_NAME}")
INTERNAL_PATH = DEVELOPMENT ? './internal' : (RUNNING_IN_PRODUCTION ? "/www/data/#{PROJECT_NAME}_internal" : "/home/qts/data/#{PROJECT_NAME}_internal")
NEO4J_DATA_PATH = File::join(DATA_PATH, 'neo4j')
NEO4J_LOGS_PATH = File::join(LOGS_PATH, 'neo4j')
RAW_FILES_PATH = File::join(DATA_PATH, 'raw')
GEN_FILES_PATH = File::join(DATA_PATH, 'gen')
VPLAN_FILES_PATH = File::join(DATA_PATH, 'vplan')

docker_compose = {
    :version => '3',
    :services => {},
}

docker_compose[:services][:nginx] = {
    :build => './docker/nginx',
    :volumes => [
        './src/static:/usr/share/nginx/html:ro',
        "#{RAW_FILES_PATH}:/raw:ro",
        "#{GEN_FILES_PATH}:/gen:ro",
        "#{LOGS_PATH}:/var/log/nginx",
    ]
}
if !DEVELOPMENT
    docker_compose[:services][:nginx][:environment] = [
        "VIRTUAL_HOST=#{WEBSITE_HOST}",
        "LETSENCRYPT_HOST=#{WEBSITE_HOST}",
        "LETSENCRYPT_EMAIL=#{LETSENCRYPT_EMAIL}"
    ]
    docker_compose[:services][:nginx][:expose] = ['80']
end
docker_compose[:services][:nginx][:links] = ["ruby:#{PROJECT_NAME}_ruby_1"]

nginx_config = <<~eos
    log_format custom '$http_x_forwarded_for - $remote_user [$time_local] "$request" '
                        '$status $body_bytes_sent "$http_referer" '
                        '"$http_user_agent" "$request_time"';

    server {
        listen 80;
        server_name localhost;
        server_tokens off;
        client_max_body_size 32M;

        access_log /var/log/nginx/access.log custom;

        charset utf-8;
    
        gzip on;
        gzip_disable "msie6";

        gzip_vary on;
        gzip_proxied expired no-cache no-store private auth;
        # compression level
        gzip_comp_level 6;
        gzip_min_length 1000;
        gzip_buffers 16 8k;
        gzip_http_version 1.1;
        # files to gzip
        gzip_types text/plain
                   text/css
                   application/json
                   application/javascript
                   text/xml 
                   application/xml 
                   application/xml+rss 
                   text/javascript
                   image/x-icon
                   image/svg+xml;

        location /raw/ {
            rewrite ^/raw(.*)$ $1 break;
            root /raw;
        }

        location /f/ {
            rewrite ^/f(.*)$ $1 break;
            root /raw/uploads/files;
        }

        location /gen/ {
            add_header Cache-Control max-age=60;
            rewrite ^/gen(.*)$ $1 break;
            root /gen;
        }

        location /ical/ {
            rewrite ^/ical(.*)$ $1 break;
            root /gen/ical;
        }

        location / {
            root /usr/share/nginx/html;
            try_files $uri @ruby;
        }

        location /favicon.ico {
            root /usr/share/nginx/html;
            expires 365d;
        }

        location @ruby {
            proxy_pass http://#{PROJECT_NAME}_ruby_1:3000;
            proxy_set_header Host $host;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection Upgrade;
        }
    }

eos
File::open('docker/nginx/default.conf', 'w') do |f|
    f.write nginx_config
end
docker_compose[:services][:nginx][:depends_on] = [:ruby]

env = []
env << 'DEVELOPMENT=1' if DEVELOPMENT
docker_compose[:services][:ruby] = {
    :build => './docker/ruby',
    :volumes => ['./src/ruby:/app:ro',
                    './src/static:/static:ro',
                    './src/data:/data:ro',
                    "#{RAW_FILES_PATH}:/raw",
                    "#{VPLAN_FILES_PATH}:/vplan",
                    "#{INTERNAL_PATH}:/internal",
                    "#{GEN_FILES_PATH}:/gen"],
    :environment => env,
    :working_dir => '/app',
    :entrypoint =>  DEVELOPMENT ?
        'rerun -b --dir /app -s SIGKILL \'thin --rackup config.ru --threaded start -e development\'' :
        'thin --rackup config.ru --threaded start -e production'
}
docker_compose[:services][:ruby][:depends_on] ||= []
docker_compose[:services][:ruby][:depends_on] << :neo4j
docker_compose[:services][:ruby][:links] = ['neo4j:neo4j']

docker_compose[:services][:neo4j] = {
    :build => './docker/neo4j',
    :volumes => ["#{NEO4J_DATA_PATH}:/data",
                 "#{NEO4J_LOGS_PATH}:/logs"]
}
docker_compose[:services][:neo4j][:environment] = [
    'NEO4J_AUTH=none',
    'NEO4J_dbms_logs__timezone=SYSTEM',
]
docker_compose[:services][:neo4j][:user] = "#{UID}"

docker_compose[:services].values.each do |x|
    x[:network_mode] = 'default'
end

docker_compose[:services][:timetable] = YAML.load(docker_compose[:services][:ruby].to_yaml)
docker_compose[:services][:timetable]['entrypoint'] = DEVELOPMENT ?
            'rerun -b --dir /app -s SIGKILL \'rackup --port 8080 --host 0.0.0.0 timetable-repl.ru\'' :
            'rackup --port 8080 --host 0.0.0.0 timetable-repl.ru'
docker_compose[:services][:ruby][:links] <<= "timetable:#{PROJECT_NAME}_timetable_1"

docker_compose[:services][:ruby][:user] = "#{UID}"
docker_compose[:services][:timetable][:user] = "#{UID}"

docker_compose[:services][:image_bot] = YAML.load(docker_compose[:services][:ruby].to_yaml)
docker_compose[:services][:image_bot]['entrypoint'] = DEVELOPMENT ?
            'rerun -b --dir /app -s SIGKILL \'rackup --port 8080 --host 0.0.0.0 image-bot-repl.ru\'' :
            'rackup --port 8080 --host 0.0.0.0 image-bot-repl.ru'
docker_compose[:services][:ruby][:links] <<= "image_bot:#{PROJECT_NAME}_image_bot_1"

docker_compose[:services][:ruby][:user] = "#{UID}"
docker_compose[:services][:timetable][:user] = "#{UID}"

docker_compose[:services][:invitation_bot] = YAML.load(docker_compose[:services][:ruby].to_yaml)
docker_compose[:services][:invitation_bot]['entrypoint'] = DEVELOPMENT ?
            'rerun -b --dir /app -s SIGKILL \'rackup --port 8080 --host 0.0.0.0 invitation-repl.ru\'' :
            'rackup --port 8080 --host 0.0.0.0 invitation-repl.ru'
docker_compose[:services][:ruby][:links] <<= "invitation_bot:#{PROJECT_NAME}_invitation_bot_1"

docker_compose[:services][:ruby][:user] = "#{UID}"
docker_compose[:services][:invitation_bot][:user] = "#{UID}"

unless `hostname`.strip == 'hetzner'
    docker_compose[:services][:mail_forwarder] = YAML.load(docker_compose[:services][:ruby].to_yaml)
    docker_compose[:services][:mail_forwarder]['entrypoint'] = DEVELOPMENT ? 'rerun -b --dir /app -s SIGTERM \'ruby mail-forwarder.rb\'' : 'ruby mail-forwarder.rb'
    docker_compose[:services][:mail_forwarder][:user] = "#{UID}"
end

if DEVELOPMENT
    docker_compose[:services][:nginx][:ports] = ["127.0.0.1:#{DEV_NGINX_PORT}:80"]
    docker_compose[:services][:neo4j][:ports] = ["127.0.0.1:#{DEV_NEO4J_PORT}:7474",
                                                 "127.0.0.1:7687:7687"]
    docker_compose[:services][:timetable][:ports] = ['127.0.0.1:8022:8080']
    docker_compose[:services][:invitation_bot][:ports] = ['127.0.0.1:8023:8080']
else
    docker_compose[:services].values.each do |x|
        x[:restart] = :always
    end
end

if RUNNING_IN_PRODUCTION
    docker_compose[:services][:nginx][:ports] = ["127.0.0.1:#{DEV_NGINX_PORT}:80"]
end


File::open('docker-compose.yaml', 'w') do |f|
    f.puts "# NOTICE: don't edit this file directly, use config.rb instead!\n"
    f.write(JSON::parse(docker_compose.to_json).to_yaml)
end

FileUtils::mkpath(LOGS_PATH)
FileUtils::cp('src/ruby/Gemfile', 'docker/ruby/')
FileUtils::mkpath(File::join(RAW_FILES_PATH, 'uploads'))
FileUtils::mkpath(File::join(RAW_FILES_PATH, 'uploads/audio_comment'))
FileUtils::mkpath(File::join(RAW_FILES_PATH, 'uploads/images'))
FileUtils::mkpath(File::join(RAW_FILES_PATH, 'uploads/files'))
FileUtils::mkpath(GEN_FILES_PATH)
FileUtils::mkpath(File::join(GEN_FILES_PATH, 'i'))
FileUtils::mkpath(VPLAN_FILES_PATH)
FileUtils::mkpath(INTERNAL_PATH)
FileUtils::mkpath(File::join(INTERNAL_PATH, 'vote'))
FileUtils::mkpath(NEO4J_DATA_PATH)
FileUtils::mkpath(NEO4J_LOGS_PATH)

system("docker-compose --project-name #{PROJECT_NAME} #{ARGV.join(' ')}")
