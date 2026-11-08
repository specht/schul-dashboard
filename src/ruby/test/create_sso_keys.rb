# Creates a throwaway SSO key pair for the test stack (called by ./test.sh).
# Logged-in pages sign the dashboard_sso cookie with
# /internal/sso-keys/sso_private.pem and fail if it is missing.

require 'openssl'
require 'fileutils'

dir = '/internal/sso-keys'
unless File.exist?(File.join(dir, 'sso_private.pem'))
    FileUtils.mkpath(dir)
    key = OpenSSL::PKey::EC.generate('prime256v1')
    File.write(File.join(dir, 'sso_private.pem'), key.to_pem)
    File.write(File.join(dir, 'sso_public.pem'), key.public_to_pem)
    puts "Created test SSO keys in #{dir}"
end
