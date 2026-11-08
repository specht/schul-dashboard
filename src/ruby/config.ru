require File.expand_path('main', File.dirname(__FILE__))

# Polled by static/errors/neustart.html while the backend restarts.
# Answered here instead of in Main so it skips the before-filter (Neo4j
# session lookups) – many open tabs poll this at once during a restart.
# It only answers once main.rb has finished loading, which is exactly
# the moment the dashboard is usable again.
map '/api/ping' do
    run lambda { |env| [200, { 'content-type' => 'text/plain', 'cache-control' => 'no-store' }, ['pong']] }
end

map '/' do
    run Main
end
