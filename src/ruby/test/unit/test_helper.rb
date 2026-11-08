# Shared setup for unit tests.
#
# The include/*.rb files reopen `class Main < Sinatra::Base` and register
# routes at load time. For unit tests we only want their helper methods, so
# Sinatra is replaced by a stub that ignores route definitions, and Main gets
# the minimal helpers those methods rely on.

require 'minitest/autorun'

module Sinatra
    class Base
        %i(get post put patch delete before after helpers configure set enable disable).each do |m|
            define_singleton_method(m) { |*_args, **_kwargs, &_block| nil }
        end
    end
end

class Main < Sinatra::Base
    def assert(condition, message = 'assertion failed', *_rest)
        raise message unless condition
    end
end

APP_ROOT = File.expand_path('../..', __dir__)

def require_app(relative_path)
    require File.join(APP_ROOT, relative_path)
end

# Tests that read /data must only ever run against the example data of the
# test stack (env.test.rb sets DASHBOARD_CREDENTIALS), never against a
# checkout with real school data mounted.
def in_test_stack?
    !ENV['DASHBOARD_CREDENTIALS'].nil? && File.exist?('/data/lehrer/lehrer.csv')
end
