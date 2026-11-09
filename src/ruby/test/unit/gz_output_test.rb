require_relative 'test_helper'
require 'tmpdir'
require 'json'
require_app 'gz_output'

class GzOutputTest < Minitest::Test
    def write(path, data)
        GzOutput.write_if_changed(path) { |f| f.print(data.to_json) }
    end

    def read(path)
        JSON.parse(Zlib::GzipReader.open(path, &:read))
    end

    def test_writes_new_and_skips_unchanged_files
        Dir.mktmpdir do |dir|
            path = File.join(dir, '2026-46.json.gz')
            assert write(path, {'events' => [1, 2]})
            assert_equal({'events' => [1, 2]}, read(path))
            mtime = File.mtime(path)
            refute write(path, {'events' => [1, 2]}), 'unchanged content must not be rewritten'
            assert_equal mtime, File.mtime(path)
        end
    end

    def test_rewrites_changed_content
        Dir.mktmpdir do |dir|
            path = File.join(dir, 'messages.json.gz')
            write(path, {'a' => 1})
            assert write(path, {'a' => 2})
            assert_equal({'a' => 2}, read(path))
        end
    end

    def test_old_files_without_checksum_are_rewritten_once
        Dir.mktmpdir do |dir|
            path = File.join(dir, 'old.json.gz')
            Zlib::GzipWriter.open(path) { |gz| gz.write('{"a":1}') }
            assert write(path, {'a' => 1}), 'files from before have no checksum yet'
            refute write(path, {'a' => 1})
        end
    end

    def test_broken_or_missing_files_are_written
        Dir.mktmpdir do |dir|
            path = File.join(dir, 'broken.json.gz')
            File.write(path, 'not gzip')
            assert write(path, {'a' => 1})
            assert_equal({'a' => 1}, read(path))
            File.unlink(path)
            assert write(path, {'a' => 1})
        end
    end

    def test_no_temporary_files_are_left
        Dir.mktmpdir do |dir|
            path = File.join(dir, 'x.json.gz')
            write(path, {'a' => 1})
            write(path, {'a' => 2})
            assert_equal ['x.json.gz'], Dir.children(dir)
        end
    end
end
