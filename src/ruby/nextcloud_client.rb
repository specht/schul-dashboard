require 'cgi'
require 'nextcloud-client'

module DashboardNextcloud
    HTTP_READ_TIMEOUT = 60 * 10
    READ_TIMEOUT_KEY = :dashboard_nextcloud_http_read_timeout

    # nextcloud-client 0.1.1 creates Net::HTTP internally and has no timeout
    # option. Keep its request implementation intact and scope the longer read
    # timeout to the current Nextcloud request only.
    module ApiReadTimeout
        def request(...)
            previous_timeout = Thread.current[READ_TIMEOUT_KEY]
            Thread.current[READ_TIMEOUT_KEY] = HTTP_READ_TIMEOUT
            super
        ensure
            Thread.current[READ_TIMEOUT_KEY] = previous_timeout
        end
    end

    module NetHttpReadTimeout
        def start(...)
            timeout = Thread.current[READ_TIMEOUT_KEY]
            self.read_timeout = timeout unless timeout.nil?
            super
        end
    end

    def self.admin
        NextcloudClient.ocs(
            url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER,
            username: NEXTCLOUD_USER,
            password: NEXTCLOUD_PASSWORD
        )
    end

    def self.as_user(username)
        NextcloudClient.ocs(
            url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER,
            username: username,
            password: NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL
        )
    end

    def self.normalize_dav_path(path)
        CGI.unescape(path.to_s).unicode_normalize(:nfc)
    end

    def self.escape_dav_segment(segment)
        CGI.escape(normalize_dav_path(segment)).gsub('+', '%20')
    end

    def self.escape_dav_path(path)
        decoded = normalize_dav_path(path)
        decoded = "/#{decoded}" unless decoded.start_with?('/')

        decoded.split('/').map { |part| escape_dav_segment(part) }.join('/')
    end

    def self.dav_uri(username, path, url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER)
        base = URI(url)
        base_path = base.path.to_s.sub(/\/+\z/, '')

        uri = base.dup
        uri.query = nil
        uri.fragment = nil
        uri.path = "#{base_path}/remote.php/dav/files/#{escape_dav_segment(username)}#{escape_dav_path(path)}"
        uri
    end
end

Net::HTTP.prepend(DashboardNextcloud::NetHttpReadTimeout) unless Net::HTTP < DashboardNextcloud::NetHttpReadTimeout
NextcloudClient::Api.prepend(DashboardNextcloud::ApiReadTimeout) unless NextcloudClient::Api < DashboardNextcloud::ApiReadTimeout
