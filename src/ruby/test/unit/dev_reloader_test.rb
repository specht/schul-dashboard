require_relative 'test_helper'
require_app 'dev_reloader'

# Hot reload in development (src/ruby/dev_reloader.rb).
class DevReloaderTest < Minitest::Test
    RUBY_DIR = File.expand_path('../..', __dir__)

    Pattern = Struct.new(:path) do
        def to_s
            path
        end
    end

    def route(path)
        [Pattern.new(path), [], proc {}]
    end

    # Reloaded files append their routes at the end – behind main.rb's
    # catch-all page route, which would then answer every GET for them.
    def test_catch_all_route_moves_back_to_the_end
        routes = {
            'GET' => [route('/api/a'), route('/*'), route('/api/b')],
            'HEAD' => [route('/*'), route('/api/b')],
            'POST' => [route('/api/c'), route('/api/d')],
        }
        DevReloader.move_catch_all_last(routes)
        assert_equal ['/api/a', '/api/b', '/*'], routes['GET'].map { |r| r[0].to_s }
        assert_equal ['/api/b', '/*'], routes['HEAD'].map { |r| r[0].to_s }
        assert_equal ['/api/c', '/api/d'], routes['POST'].map { |r| r[0].to_s }
    end

    # The reloader must never be active in production: only dev_reloader.rb
    # may load it, and only behind DEVELOPMENT and DASHBOARD_HOT_RELOAD.
    def test_reloader_is_only_loaded_behind_the_development_guard
        users = Dir[File.join(RUBY_DIR, '**', '*.rb')].reject { |p| p.include?('/test/') }.select do |path|
            File.read(path, encoding: 'utf-8').include?('sinatra/reloader')
        end
        assert_equal ['dev_reloader.rb'], users.map { |p| p.sub(RUBY_DIR + '/', '') }
        source = File.read(File.join(RUBY_DIR, 'dev_reloader.rb'), encoding: 'utf-8')
        guard = source[/^if .*$/]
        assert_includes guard, 'DEVELOPMENT'
        assert_includes guard, "ENV['DASHBOARD_HOT_RELOAD'] == '1'"
        refute_includes source.sub(/^if .*\z/m, ''), 'register', 'register only inside the guard'
    end
end
