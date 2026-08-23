#!/usr/bin/env ruby

require 'fileutils'

repository_root = File.expand_path('../..', __dir__)
load File.join(repository_root, 'env.rb')

run_ruby = lambda do
    system(
        './config.rb',
        'exec',
        '-e',
        'DASHBOARD_SERVICE=script',
        'ruby',
        'ruby',
        'share-nc-folders.rb',
        *ARGV,
        chdir: repository_root
    )
end

unless ARGV.include?('--srsly')
    exit(run_ruby.call ? 0 : 1)
end

unless defined?(NEXTCLOUD_INSTALL_PATH) && NEXTCLOUD_INSTALL_PATH && !NEXTCLOUD_INSTALL_PATH.empty?
    warn 'NEXTCLOUD_INSTALL_PATH is not configured in env.rb; cannot use Nextcloud native share moves.'
    exit 1
end

php_command = if defined?(NEXTCLOUD_PHP_COMMAND) && NEXTCLOUD_PHP_COMMAND
    Array(NEXTCLOUD_PHP_COMMAND)
else
    ['sudo', '--user', 'www-data', '/usr/bin/php']
end

internal_path = File.expand_path(INTERNAL_PATH, repository_root)
rpc_dir = File.join(internal_path, 'nextcloud-share-move-rpc')
requests_dir = File.join(rpc_dir, 'requests')
responses_dir = File.join(rpc_dir, 'responses')
ready_path = File.join(rpc_dir, 'ready')
stop_path = File.join(rpc_dir, 'stop')
worker_path = File.join(repository_root, 'src/scripts/nextcloud-share-move-worker.php')

FileUtils.rm_rf(rpc_dir)
FileUtils.mkdir_p([requests_dir, responses_dir])
FileUtils.chmod(0o777, [rpc_dir, requests_dir, responses_dir])

worker_pid = Process.spawn(
    *php_command,
    worker_path,
    NEXTCLOUD_INSTALL_PATH,
    rpc_dir,
    chdir: repository_root
)

begin
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    until File.exist?(ready_path)
        finished = Process.waitpid(worker_pid, Process::WNOHANG)
        if finished
            warn 'Nextcloud native share move worker exited before becoming ready.'
            exit 1
        end

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            warn 'Timed out waiting for Nextcloud native share move worker.'
            Process.kill('TERM', worker_pid) rescue nil
            Process.wait(worker_pid) rescue nil
            exit 1
        end

        sleep 0.05
    end

    success = run_ruby.call
ensure
    FileUtils.touch(stop_path)
    Process.wait(worker_pid) rescue nil
    FileUtils.rm_rf(rpc_dir)
end

exit(success ? 0 : 1)
