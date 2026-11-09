# Safety net for development instances, which may hold a copy of the real
# data: mails sent from there may only reach the addresses on
# DEVELOPMENT_MAIL_DELIVERY_POSITIVE_LIST. Every code path that sends mail
# goes through deliver_with_development_guard! (main.rb).
module MailGuard
    FIELDS = [:to, :cc, :bcc]

    # Removes every recipient (to, cc, bcc) that is not on `allowed` and pins
    # the SMTP envelope to the remaining ones, so nothing else can be added
    # on the way. Returns the removed addresses.
    def self.restrict!(mail, allowed)
        allowed = allowed.map { |address| address.to_s.strip.downcase }
        removed = []
        FIELDS.each do |field|
            addresses = Array(mail.public_send(field)).compact
            kept, dropped = addresses.partition { |address| allowed.include?(address.to_s.strip.downcase) }
            removed.concat(dropped)
            mail.public_send("#{field}=", kept.empty? ? nil : kept)
        end
        mail.smtp_envelope_to = recipients(mail) if deliverable?(mail)
        removed
    end

    def self.recipients(mail)
        FIELDS.flat_map { |field| Array(mail.public_send(field)).compact }
    end

    # Only send if someone the mail is addressed to (to/cc) is allowed. An
    # allowed bcc alone (e.g. the dashboard's own address, which gets a copy
    # of most mails) must not make a mail to somebody else go out.
    def self.deliverable?(mail)
        [:to, :cc].any? { |field| !Array(mail.public_send(field)).compact.empty? }
    end
end
