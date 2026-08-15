require 'minitest/autorun'

NEXTCLOUD_URL_FROM_RUBY_CONTAINER = 'https://cloud.example.test' unless defined?(NEXTCLOUD_URL_FROM_RUBY_CONTAINER)
NEXTCLOUD_USER = 'Dashboard' unless defined?(NEXTCLOUD_USER)
NEXTCLOUD_PASSWORD = 'admin-password' unless defined?(NEXTCLOUD_PASSWORD)
NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL = 'user-password' unless defined?(NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL)

require_relative 'nextcloud_client'

class NextcloudClientCompatibilityTest < Minitest::Test
    OCS_META = <<~XML
        <meta>
          <status>ok</status>
          <statuscode>200</statuscode>
          <message>OK</message>
        </meta>
    XML

    def test_factories_and_expected_api_methods
        admin = DashboardNextcloud.admin
        user = DashboardNextcloud.as_user('joerg')

        assert_instance_of NextcloudClient::OcsApi, admin
        assert_instance_of NextcloudClient::OcsApi, user
        assert_respond_to admin.user, :all
        assert_respond_to admin.user, :find
        assert_respond_to admin.user, :create
        assert_respond_to admin.user, :update
        assert_respond_to admin.user('joerg').group, :create
        assert_respond_to admin.user('joerg').group, :destroy
        assert_respond_to admin.group, :all
        assert_respond_to admin.group, :create
        assert_respond_to admin.file_sharing, :all
        assert_respond_to admin.file_sharing, :specific
        assert_respond_to admin.file_sharing, :create
        assert_respond_to admin.file_sharing, :update_permissions
        assert_respond_to admin.file_sharing, :destroy
        assert_respond_to user.webdav.directory, :find
        assert_respond_to user.webdav.directory, :create
        assert_respond_to user.webdav.directory, :destroy
        assert_respond_to user.webdav.directory, :move
    end

    def test_user_model_fields
        ocs = DashboardNextcloud.admin
        response = Nokogiri::XML(<<~XML)
            <ocs>
              #{OCS_META}
              <data>
                <enabled>true</enabled>
                <id>joerg</id>
                <email>joerg@example.test</email>
                <displayname>Jörg Example</displayname>
                <groups><element>Lehrer</element><element>Lehrer 10a</element></groups>
              </data>
            </ocs>
        XML
        ocs.define_singleton_method(:request) { |*| response }

        user = ocs.user.find('joerg')

        assert_equal 'joerg', user.id
        assert_equal 'Jörg Example', user.displayname
        assert_equal 'joerg@example.test', user.email
        assert_equal ['Lehrer', 'Lehrer 10a'], user.groups
    end

    def test_share_fields_keep_string_keys
        sharing = DashboardNextcloud.admin.file_sharing
        response = Nokogiri::XML(<<~XML)
            <ocs>
              #{OCS_META}
              <data>
                <element>
                  <id>42</id>
                  <share_type>0</share_type>
                  <share_with>joerg</share_with>
                  <uid_owner>Dashboard</uid_owner>
                  <path>/Unterricht/Deutsch</path>
                  <file_target>/Unterricht/Deutsch</file_target>
                  <permissions>15</permissions>
                </element>
              </data>
            </ocs>
        XML
        sharing.define_singleton_method(:request) { |*| response }

        share = sharing.all.fetch(0)

        expected = {
            'id' => '42',
            'share_type' => '0',
            'share_with' => 'joerg',
            'uid_owner' => 'Dashboard',
            'path' => '/Unterricht/Deutsch',
            'file_target' => '/Unterricht/Deutsch',
            'permissions' => '15'
        }
        assert_equal expected, share.slice(*expected.keys)
        assert_equal expected, sharing.specific('/Unterricht/Deutsch').fetch(0).slice(*expected.keys)
    end

    def test_webdav_directory_models_and_success_returns
        webdav = NextcloudClient.webdav(
            url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER,
            username: 'joerg',
            password: NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL
        )
        listing = Nokogiri::XML(<<~XML)
            <d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
              <d:response>
                <d:href>/remote.php/dav/files/joerg/Unterricht/</d:href>
                <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
              </d:response>
              <d:response>
                <d:href>/remote.php/dav/files/joerg/Unterricht/R%C3%BCckgabe/</d:href>
                <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
              </d:response>
            </d:multistatus>
        XML
        webdav.define_singleton_method(:request) { |*| listing }

        directory = webdav.directory.find('/Unterricht')

        assert_equal 'collection', directory.resourcetype
        assert_equal 1, directory.contents.size
        assert_equal '/remote.php/dav/files/joerg/Unterricht/R%C3%BCckgabe/', directory.contents.first.href
        assert_equal 'collection', directory.contents.first.resourcetype

        empty_success = Nokogiri::XML('')
        webdav.define_singleton_method(:request) { |*| empty_success }
        assert_equal({ status: 'ok' }, webdav.directory.move('/Unterricht', '/Archiv'))
        assert_equal({ status: 'ok' }, webdav.directory.destroy('/Archiv'))
    end

    def test_timeout_patch_is_scoped_to_nextcloud_requests
        http_probe = Class.new do
            attr_accessor :read_timeout

            def start
                [read_timeout, Thread.current[DashboardNextcloud::READ_TIMEOUT_KEY]]
            end
        end
        http_probe.prepend(DashboardNextcloud::NetHttpReadTimeout)

        request_probe = Class.new do
            def initialize(http_class)
                @http_class = http_class
            end

            def request
                @http_class.new.start
            end
        end
        request_probe.prepend(DashboardNextcloud::ApiReadTimeout)

        assert_equal [600, 600], request_probe.new(http_probe).request
        assert_nil Thread.current[DashboardNextcloud::READ_TIMEOUT_KEY]
    end

    def test_raw_webdav_uri_escapes_each_unicode_segment
        uri = DashboardNextcloud.dav_uri(
            'jörg example',
            '/Rückgabe/Übung & 1',
            url: 'https://cloud.example.test:8443/nextcloud/'
        )

        assert_equal 'https', uri.scheme
        assert_equal 8443, uri.port
        assert_equal '/nextcloud/remote.php/dav/files/j%C3%B6rg%20example/R%C3%BCckgabe/%C3%9Cbung%20%26%201', uri.path
    end
end
