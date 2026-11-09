# Hot reload for development: with DEV_HOT_RELOAD = true in env.rb, config.rb
# gives the web service DASHBOARD_HOT_RELOAD=1 and makes rerun ignore
# include/. Changed files in include/ are then reloaded on the next request
# (Sinatra::Reloader) instead of restarting the service with a full
# collect_data. Everything else (main.rb, parser.rb, …) still restarts the
# service through rerun. Never active in production.
#
# Limits (development only, see doc/Development.md):
# - startup code is not run again: data from collect_data, configure blocks
#   and class variables set at startup stay as they are;
# - removed or renamed methods stay defined until the next restart;
# - the bots still restart on every change (they load the same code).

module DevReloader
    # Reloaded files append their routes at the end – behind main.rb's
    # catch-all page route get '/*', which would then answer every GET request
    # for them. Move catch-all routes back to the end of each list.
    def self.move_catch_all_last(routes)
        routes.each_value do |list|
            catch_all, rest = list.partition { |route| route[0].to_s == '/*' }
            list.replace(rest + catch_all)
        end
        routes
    end
end

if defined?(DEVELOPMENT) && DEVELOPMENT && ENV['DASHBOARD_HOT_RELOAD'] == '1'
    require 'sinatra/reloader'

    class Main < Sinatra::Base
        # registered before include/*.rb and the routes of main.rb are loaded, so
        # that it sees all of them and its before filter runs first
        register Sinatra::Reloader
        # rackup runs with --env production, where the reloader is off by default
        set :reloader, true
        also_reload './include/*.rb'
        # never reload files with startup code – rerun restarts the service for them
        dont_reload './*.rb'

        after_reload do |paths|
            DevReloader.move_catch_all_last(routes)
            debug "Hot reload: #{paths.map { |p| File.basename(p) }.join(', ')} (startup data unchanged)"
        end
    end
    STDERR.puts 'Hot reload for include/*.rb is on (DEV_HOT_RELOAD)'
end
