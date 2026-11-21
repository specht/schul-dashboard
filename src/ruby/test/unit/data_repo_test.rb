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
end
