require_relative 'test_helper'
require 'tmpdir'
require 'open3'
require_app 'data_repo'

# Writing, committing and rolling back files in the data repo
# (data_repo.rb, used by /datenpflege). Throwaway repos only.
class DataRepoTest < Minitest::Test
    def setup
        _, status = Open3.capture2e('git', '--version')
        skip 'git missing' unless status.success?
    rescue Errno::ENOENT
        skip 'git missing'
    end

    def with_repo
        Dir.mktmpdir do |root|
            DataRepo.git(root, 'init', '-q')
            Dir.mkdir(File.join(root, 'schueler'))
            File.write(File.join(root, 'schueler', 'ASCII.TXT'), "alt\n")
            File.write(File.join(root, 'schueler', 'notizen.txt'), "nicht von uns\n")
            DataRepo.git(root, 'add', '-A')
            DataRepo.git(root, 'commit', '-q', '-m', 'Anfang')
            yield root
        end
    end

    def test_writable_needs_a_git_checkout
        Dir.mktmpdir { |dir| refute DataRepo.writable?(dir) }
        with_repo { |root| assert DataRepo.writable?(root) }
    end

    def test_paths_stay_inside_the_repo
        ['../x', '/etc/passwd', 'schueler/../../x', 'a b', '', nil].each do |rel|
            assert_raises(DataRepo::Error, rel.inspect) { DataRepo.check_path!(rel) }
        end
        assert_equal 'schueler/2026-11-20.TXT', DataRepo.check_path!('schueler/2026-11-20.TXT')
    end

    def test_commit_takes_only_the_given_files
        with_repo do |root|
            DataRepo.write(root, 'schueler/2026-11-20.TXT', "neu\n")
            File.write(File.join(root, 'schueler', 'notizen.txt'), "geändert, aber nicht von uns\n")
            assert_equal({ 'schueler/2026-11-20.TXT' => 'neu' },
                         DataRepo.uncommitted(root, ['schueler/2026-11-20.TXT']))
            result = DataRepo.commit(root, ['schueler/2026-11-20.TXT'], 'Schüler:innen: 2026-11-20.TXT')
            assert_match(/\A[0-9a-f]+\z/, result[:commit])
            refute result[:pushed]
            assert_empty DataRepo.uncommitted(root, ['schueler/2026-11-20.TXT'])
            # the other change is still there, uncommitted
            assert_equal({ 'schueler/notizen.txt' => 'geändert' }, DataRepo.uncommitted(root, ['schueler']))
            assert_equal 'Schüler:innen: 2026-11-20.TXT', DataRepo.log(root, 'schueler/2026-11-20.TXT').first[:subject]
            assert_equal 'Dashboard', DataRepo.log(root, 'schueler/2026-11-20.TXT').first[:author]
        end
    end

    def test_rollback_removes_new_and_restores_changed_files
        with_repo do |root|
            DataRepo.write(root, 'schueler/2026-11-20.TXT', "neu\n")
            DataRepo.write(root, 'schueler/ASCII.TXT', "überschrieben\n")
            rolled = DataRepo.rollback(root, ['schueler/2026-11-20.TXT', 'schueler/ASCII.TXT'])
            assert_equal ['schueler/2026-11-20.TXT', 'schueler/ASCII.TXT'], rolled.sort
            refute File.exist?(File.join(root, 'schueler', '2026-11-20.TXT'))
            assert_equal "alt\n", File.read(File.join(root, 'schueler', 'ASCII.TXT'))
        end
    end

    def test_commit_without_changes_is_refused
        with_repo do |root|
            assert_raises(DataRepo::Error) { DataRepo.commit(root, ['schueler/ASCII.TXT'], 'nichts') }
        end
    end

    # pushing uses the deploy key when there is one (and only that key)
    def test_push_uses_the_deploy_key
        Dir.mktmpdir do |dir|
            key = File.join(dir, 'key')
            refute_includes DataRepo.git_env(key)['GIT_SSH_COMMAND'], '-i'
            File.write(key, 'x')
            assert_includes DataRepo.git_env(key)['GIT_SSH_COMMAND'], "-i #{key} -o IdentitiesOnly=yes"
        end
    end

    # committed changes are counted until pushed; a deletion is committed too
    def test_push_and_unpushed
        Dir.mktmpdir do |dir|
            remote = File.join(dir, 'remote.git')
            DataRepo.git(dir, 'init', '-q', '--bare', remote)
            with_repo do |root|
                assert_nil DataRepo.unpushed(root)
                branch = DataRepo.git(root, 'rev-parse', '--abbrev-ref', 'HEAD').strip
                DataRepo.git(root, 'remote', 'add', 'origin', remote)
                DataRepo.git(root, 'push', '-q', '-u', 'origin', branch)
                assert_equal 0, DataRepo.unpushed(root)
                DataRepo.write(root, 'schueler/2099-01-01.TXT', "neu\n")
                DataRepo.commit(root, ['schueler/2099-01-01.TXT'], 'Liste')
                assert_equal 1, DataRepo.unpushed(root)
                DataRepo.push(root)
                assert_equal 0, DataRepo.unpushed(root)
                File.delete(File.join(root, 'schueler', '2099-01-01.TXT'))
                assert_equal({ 'schueler/2099-01-01.TXT' => 'gelöscht' }, DataRepo.uncommitted(root, ['schueler/2099-01-01.TXT']))
                DataRepo.commit(root, ['schueler/2099-01-01.TXT'], 'weg')
                assert_empty DataRepo.uncommitted(root, ['schueler/2099-01-01.TXT'])
                assert_equal 1, DataRepo.unpushed(root)
            end
        end
    end

    # pushing pulls the others' commits first – also with somebody's own
    # changes lying around in the checkout (kept, not committed)
    def test_push_with_others_changes_and_new_commits
        Dir.mktmpdir do |dir|
            remote = File.join(dir, 'remote.git')
            other = File.join(dir, 'other')
            DataRepo.git(dir, 'init', '-q', '--bare', remote)
            with_repo do |root|
                branch = DataRepo.git(root, 'rev-parse', '--abbrev-ref', 'HEAD').strip
                DataRepo.git(root, 'remote', 'add', 'origin', remote)
                DataRepo.git(root, 'push', '-q', '-u', 'origin', branch)
                # someone else pushed meanwhile
                DataRepo.git(dir, 'clone', '-q', remote, other)
                File.write(File.join(other, 'schueler', 'ASCII.TXT'), "von woanders\n")
                DataRepo.git(other, 'commit', '-q', '-am', 'anderswo')
                DataRepo.git(other, 'push', '-q')
                # a change of the maintainer's own, not committed
                File.write(File.join(root, 'schueler', 'notizen.txt'), "geändert, nicht von uns\n")
                DataRepo.write(root, 'schueler/2099-01-01.TXT', "neu\n")
                ENV['DASHBOARD_DATA_REPO_PUSH'] = '1'
                result = begin
                    DataRepo.commit(root, ['schueler/2099-01-01.TXT'], 'Liste')
                ensure
                    ENV.delete('DASHBOARD_DATA_REPO_PUSH')
                end
                assert result[:pushed], result[:push_error].to_s
                assert_equal 0, DataRepo.unpushed(root)
                assert_equal "von woanders\n", File.read(File.join(root, 'schueler', 'ASCII.TXT'))
                assert_equal "geändert, nicht von uns\n", File.read(File.join(root, 'schueler', 'notizen.txt'))
            end
        end
    end
end
