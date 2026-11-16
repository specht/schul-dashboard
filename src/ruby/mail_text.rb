require 'cgi'

module MailText
    # the plain text part of an HTML mail (deliver_mail in main.rb); entities
    # like &amp; become characters again
    def self.html_to_plain_text(s)
        CGI.unescapeHTML(s.gsub('<p>', "\n\n").gsub(/<br\s*\/?>/, "\n").gsub(/<\/?[^>]*>/, '').strip)
    end
end
