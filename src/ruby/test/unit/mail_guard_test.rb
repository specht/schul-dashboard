require_relative 'test_helper'
require 'mail'
require_app 'mail_guard'

# Mails from a development instance must only reach the positive list.
class MailGuardTest < Minitest::Test
    ALLOWED = ['Me@Example.org ']

    def mail(to: [], cc: [], bcc: [])
        Mail.new do
            from 'dashboard@example.org'
            to to unless to.empty?
            cc cc unless cc.empty?
            bcc bcc unless bcc.empty?
            subject 'Test'
            body 'Hallo'
        end
    end

    def test_removes_everybody_else_from_to_cc_and_bcc
        m = mail(to: ['me@example.org', 'student@example.org'], cc: ['parent@example.org'],
                 bcc: ['dashboard@example.org', 'ME@example.org'])
        removed = MailGuard.restrict!(m, ALLOWED)
        assert_equal ['student@example.org', 'parent@example.org', 'dashboard@example.org'], removed
        assert_equal ['me@example.org'], Array(m.to)
        assert_empty Array(m.cc)
        assert_equal ['ME@example.org'], Array(m.bcc)
        assert MailGuard.deliverable?(m)
        # the SMTP envelope is pinned to the remaining recipients
        assert_equal ['me@example.org', 'ME@example.org'], Array(m.smtp_envelope_to)
    end

    def test_first_recipient_allowed_is_not_enough
        # the old rule only looked at the first "to" address
        m = mail(to: ['me@example.org', 'teacher@example.org'])
        MailGuard.restrict!(m, ALLOWED)
        assert_equal ['me@example.org'], Array(m.to)
    end

    def test_nobody_allowed_means_not_deliverable
        m = mail(to: ['student@example.org'], bcc: ['dashboard@example.org'])
        MailGuard.restrict!(m, ALLOWED)
        refute MailGuard.deliverable?(m)
        assert_empty MailGuard.recipients(m)
    end

    def test_allowed_bcc_alone_does_not_send_a_mail_to_somebody_else
        # e.g. a login code for a student with a bcc to the dashboard's own,
        # allowed address: must not go out at all
        m = mail(to: ['student@example.org'], bcc: ['me@example.org'])
        MailGuard.restrict!(m, ALLOWED)
        refute MailGuard.deliverable?(m)
    end

    def test_empty_positive_list_blocks_everything
        m = mail(to: ['me@example.org'])
        MailGuard.restrict!(m, [])
        refute MailGuard.deliverable?(m)
    end
end
