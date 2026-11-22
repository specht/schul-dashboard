# The data repo (the input data, mounted read-only at /data) as seen by the
# web service when it may write to it: a second mount at /data-repo
# (DATA_REPO_WRITABLE in env.rb, see config.rb). Uploads on /datenpflege
# write their files here; they are visible under /data at once (same
# directory), but only become part of the repo's history when committed.
#
# git always runs with an argument list, never through a shell.

require 'open3'
require 'securerandom'

module DataRepo
    PATH = '/data-repo'

    class Error < StandardError; end

    def self.root
        PATH
    end

    def self.writable?(root = PATH)
        File.directory?(File.join(root, '.git')) && File.writable?(root)
    end

    def self.push?
        ENV['DASHBOARD_DATA_REPO_PUSH'] == '1'
    end

    # The key for pushing (DATA_REPO_PUSH): a deploy key with write access to
    # the data repo only, kept outside every repository (INTERNAL_PATH is
    # /internal in the container). It must belong to the service's user and
    # be readable by it alone (chmod 600) – ssh refuses it otherwise.
    DEPLOY_KEY = '/internal/data-repo-deploy-key'

    def self.git_env(key = DEPLOY_KEY)
        ssh = ['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new']
        ssh += ['-i', key, '-o', 'IdentitiesOnly=yes'] if File.exist?(key)
        {
            'HOME' => '/tmp',
            'GIT_TERMINAL_PROMPT' => '0',
            'GIT_SSH_COMMAND' => ssh.join(' '),
        }
    end

    def self.git(root, *args)
        out, status = Open3.capture2e(git_env, 'git', '-C', root,
                                      '-c', 'user.name=Dashboard',
                                      '-c', 'user.email=dashboard@localhost',
                                      *args)
        raise Error, "git #{args.first}: #{out.strip}" unless status.success?
        out
    end

    # Only paths below the repo, no '..' and no absolute paths.
    def self.check_path!(rel)
        unless rel.is_a?(String) && rel =~ %r{\A[A-Za-z0-9_\-]+(/[A-Za-z0-9_\-.]+)*\z} && !rel.split('/').include?('..')
            raise Error, "invalid path: #{rel.inspect}"
        end
        rel
    end

    def self.write(root, rel, content)
        check_path!(rel)
        path = File.join(root, rel)
        tmp = "#{path}.#{SecureRandom.hex(4)}.tmp"
        File.write(tmp, content, encoding: 'UTF-8')
        File.rename(tmp, path)
        path
    end

    # rel => 'neu' (untracked) or 'geändert' for the given paths with changes
    # that are not committed.
    def self.uncommitted(root, rels)
        rels = rels.map { |r| check_path!(r) }
        return {} if rels.empty?
        result = {}
        git(root, 'status', '--porcelain', '--untracked-files=all', '--', *rels).each_line do |line|
            code = line[0, 2]
            rel = line[3..].strip
            result[rel] = code == '??' ? 'neu' : (code.include?('D') ? 'gelöscht' : 'geändert')
        end
        result
    end

    # Commits exactly these paths (nothing else that may be staged or
    # changed in the checkout) and pushes if configured. Returns
    # {:commit => hash, :pushed => bool, :push_error => text or nil}.
    def self.commit(root, rels, message)
        rels = rels.map { |r| check_path!(r) }
        raise Error, 'nothing to commit' if uncommitted(root, rels).empty?
        git(root, 'add', '--', *rels)
        git(root, 'commit', '-q', '-m', message, '--only', '--', *rels)
        hash = git(root, 'rev-parse', '--short', 'HEAD').strip
        result = { :commit => hash, :pushed => false, :push_error => nil }
        if push?
            begin
                git(root, 'pull', '-q', '--rebase')
                git(root, 'push', '-q')
                result[:pushed] = true
            rescue Error => e
                result[:push_error] = e.message
            end
        end
        result
    end

    # Pushes what was committed (after pulling the others' commits). Raises
    # Error if it fails.
    def self.push(root)
        git(root, 'pull', '-q', '--rebase')
        git(root, 'push', '-q')
    end

    # Commits not pushed yet (nil without an upstream branch)
    def self.unpushed(root)
        git(root, 'rev-list', '--count', '@{u}..HEAD').strip.to_i
    rescue Error
        nil
    end

    # Undoes uncommitted changes of these paths: new files are removed,
    # changed or deleted ones restored from the last commit.
    def self.rollback(root, rels)
        changes = uncommitted(root, rels)
        changes.each_pair do |rel, state|
            if state == 'neu'
                File.delete(File.join(root, rel))
            else
                git(root, 'restore', '--staged', '--worktree', '--source=HEAD', '--', rel)
            end
        end
        changes.keys
    end

    # [{:commit, :date, :author, :subject}] of the last commits touching rel.
    def self.log(root, rel, limit = 20)
        check_path!(rel)
        git(root, 'log', "-#{limit.to_i}", '--format=%h%x09%aI%x09%an%x09%s', '--', rel).lines.map do |line|
            commit, date, author, subject = line.chomp.split("\t", 4)
            { :commit => commit, :date => date, :author => author, :subject => subject }
        end
    end
end
