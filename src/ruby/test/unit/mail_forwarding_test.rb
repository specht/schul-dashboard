require_relative 'test_helper'
require_app 'mail_forwarding'
require 'tmpdir'

class MailForwardingTest < Minitest::Test
    # an HTML mail with a PDF attachment from outside the school, sent to a list
    def external_mail
        mail = Mail.new do
            from 'Eva Extern <eva@example.org>'
            to 'eltern.5a@verteiler.example.com'
            subject 'Ausflug'
            text_part { body 'Hallo zusammen' }
            html_part do
                content_type 'text/html; charset=UTF-8'
                body '<p>Hallo <b>zusammen</b></p>'
            end
            add_file filename: 'plan.pdf', content: "%PDF-1.4 test"
        end
        mail.header['DKIM-Signature'] = 'v=1; d=example.org; b=abc'
        mail.to_s
    end

    def test_copy_keeps_multipart_and_attachments
        copy = MailForwarding.copy_for(external_mail, 'max@example.com', own_domain: false,
                                       sender_for_foreign: 'verteiler@example.com')
        assert copy.multipart?
        assert_equal ['plan.pdf'], copy.attachments.map(&:filename)
        assert_includes copy.html_part.decoded, '<b>zusammen</b>'
        assert_equal ['max@example.com'], copy.to
        assert_equal ['verteiler@example.com'], copy.from
        assert_equal ['eva@example.org'], copy.reply_to
        assert_nil copy.header['DKIM-Signature']
        assert_empty copy.cc.to_a
    end

    def test_copy_from_own_domain_keeps_the_sender
        copy = MailForwarding.copy_for(external_mail, 'max@example.com', own_domain: true)
        assert_equal ['eva@example.org'], copy.from
    end

    def test_storage_dir_is_safe_for_every_message_id
        a = MailForwarding.storage_dir('<abc/def@example.org>', 'x', '/mails')
        b = MailForwarding.storage_dir('<other@example.org>', 'x', '/mails')
        assert_match %r{\A/mails/[0-9a-f]{40}\z}, a
        refute_equal a, b
        # without Message-ID the content decides – two different mails don't collide
        refute_equal MailForwarding.storage_dir(nil, 'mail one'), MailForwarding.storage_dir(nil, 'mail two')
        assert_equal MailForwarding.storage_dir(nil, 'same'), MailForwarding.storage_dir('', 'same')
    end

    def test_a_mail_counts_as_handled_only_when_complete
        Dir.mktmpdir do |dir|
            File.write(File.join(dir, 'mail'), 'raw')
            refute MailForwarding.handled?(dir), 'only the mail file: processing was interrupted'
            File.write(File.join(dir, 'recipients.yaml.tmp'), 'half')
            refute MailForwarding.handled?(dir), 'an interrupted write does not count'
            File.unlink(File.join(dir, 'recipients.yaml.tmp'))
            MailForwarding.write_atomically(File.join(dir, 'recipients.yaml'), {:pending => ['a']}.to_yaml)
            assert MailForwarding.handled?(dir)
            assert_equal ['mail', 'recipients.yaml'], Dir.children(dir).sort
        end
        Dir.mktmpdir do |dir|
            MailForwarding.mark_handled(dir) # e.g. bounced, no recipients
            assert MailForwarding.handled?(dir)
        end
        Dir.mktmpdir do |dir|
            File.write(File.join(dir, 'recipients.yaml.archived'), '') # stored before the marker existed
            assert MailForwarding.handled?(dir)
        end
    end

    def state(*pending)
        { :pending => pending, :sent => [] }
    end

    def test_everyone_gets_it
        s = state('a', 'b', 'c')
        sent = []
        assert_equal :done, MailForwarding.deliver_pending(s) { |r| sent << r }
        assert_equal %w(a b c), sent
        assert_equal %w(a b c), s[:sent]
        assert_empty s[:pending]
    end

    def test_a_refused_address_does_not_stop_the_others
        s = state('a', 'kaputt', 'c')
        result = MailForwarding.deliver_pending(s) do |r|
            raise Net::SMTPFatalError, '550 no such user' if r == 'kaputt'
        end
        assert_equal :done, result
        assert_equal %w(a c), s[:sent]
        assert_equal %w(kaputt), s[:failed]
    end

    def test_temporary_error_pauses_and_continues_later
        s = state('a', 'b', 'c')
        calls = 0
        result = MailForwarding.deliver_pending(s, now: 1000) do |r|
            calls += 1
            raise Net::SMTPServerBusy, '451 rate limit' if r == 'b'
        end
        assert_equal :retry_later, result
        assert_equal %w(a), s[:sent]
        assert_equal %w(b c), s[:pending]
        assert_equal 1000 + MailForwarding.retry_pause(1), s[:retry_at]
        # too early: nothing happens
        assert_equal :not_yet, MailForwarding.deliver_pending(s, now: 1001) { |_| flunk 'sent too early' }
        # later: the rest goes out
        assert_equal :done, MailForwarding.deliver_pending(s, now: s[:retry_at]) { |_| }
        assert_equal %w(a b c), s[:sent]
        assert_nil s[:retry_at]
    end

    def test_gives_up_after_many_attempts
        s = state('a')
        now = 0
        result = nil
        MailForwarding::MAX_ATTEMPTS.times do
            result = MailForwarding.deliver_pending(s, now: now) { |_| raise Net::ReadTimeout }
            now = s[:retry_at] || now
        end
        assert_equal :gave_up, result
        assert_equal %w(a), s[:pending]
    end

    def test_progress_is_saved_after_every_recipient
        s = state('a', 'b')
        saved = []
        MailForwarding.deliver_pending(s, on_progress: ->(st) { saved << st[:sent].dup }) { |_| }
        assert_equal [%w(a), %w(a b)], saved
    end
end
