require 'mail'
require 'net/smtp'
require 'socket'
require 'timeout'
require 'openssl'

# Sending part of the mail forwarder (mail-forwarder.rb): a mail to a mailing
# list address is stored once and then sent to every member separately.
#
# - copy_for: the copy for one member keeps the original intact (multipart,
#   attachments). Mails from outside the school's domains get our own sender
#   address (the provider would refuse foreign senders), the original sender
#   becomes Reply-To.
# - deliver_pending: sends to the pending members of one stored mail. A
#   member's address that is refused permanently is skipped; temporary errors
#   (provider busy or limiting, timeouts, lost connections) stop this pass and
#   the rest is retried later, with growing pauses, until MAX_ATTEMPTS.
module MailForwarding
    MAX_ATTEMPTS = 8
    # pause after the n-th failed attempt: 2, 4, 8 … minutes, at most 60
    def self.retry_pause(attempts)
        [2**attempts, 60].min * 60
    end

    TEMPORARY_ERRORS = [
        Net::SMTPServerBusy, Net::SMTPUnknownError, Net::OpenTimeout, Net::ReadTimeout,
        Timeout::Error, EOFError, IOError, SocketError, SystemCallError, OpenSSL::SSL::SSLError,
    ].freeze
    # only this address is refused (5xx) – the others can still be sent
    RECIPIENT_ERRORS = [Net::SMTPFatalError, Net::SMTPSyntaxError].freeze

    # headers of the original transport that are wrong for a copy we send ourselves
    TRANSPORT_HEADERS = %w(DKIM-Signature ARC-Seal ARC-Message-Signature ARC-Authentication-Results
                           Authentication-Results Return-Path Sender Delivered-To X-Original-To).freeze

    def self.copy_for(raw, recipient, own_domain:, sender_for_foreign: nil)
        mail = Mail.read_from_string(raw)
        original_from = mail[:from].formatted.first
        mail.to = recipient
        mail.cc = []
        mail.bcc = []
        mail.reply_to = original_from
        TRANSPORT_HEADERS.each do |name|
            mail.header[name] = nil while mail.header[name]
        end
        mail.from = sender_for_foreign unless own_domain
        mail
    end

    # state: {:pending => [...], :sent => [...], :failed => [...], :attempts => n,
    #         :retry_at => unix time} (recipients.yaml). Yields each pending
    # recipient to the block, which sends the mail; after every recipient the
    # block given as on_progress may write the state to disk.
    # Returns :done, :retry_later, :gave_up or :not_yet (pause still running).
    def self.deliver_pending(state, now: Time.now.to_i, on_progress: nil, log: nil)
        state[:sent] ||= []
        state[:failed] ||= []
        state[:attempts] ||= 0
        return :not_yet if state[:retry_at] && now < state[:retry_at]
        until state[:pending].empty?
            recipient = state[:pending].first
            begin
                yield recipient
                state[:pending].shift
                state[:sent] << recipient
            rescue *RECIPIENT_ERRORS => e
                log&.call("Refused for #{recipient}: #{e.class}: #{e.message.to_s.strip}")
                state[:pending].shift
                state[:failed] << recipient
            rescue *TEMPORARY_ERRORS => e
                state[:attempts] += 1
                log&.call("Temporary error (attempt #{state[:attempts]}): #{e.class}: #{e.message.to_s.strip}")
                return :gave_up if state[:attempts] >= MAX_ATTEMPTS
                state[:retry_at] = now + retry_pause(state[:attempts])
                on_progress&.call(state)
                return :retry_later
            end
            on_progress&.call(state)
        end
        state.delete(:retry_at)
        :done
    end
end
