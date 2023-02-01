gem 'docx'

# d = Docx::Document.open('example.docx')
# d.paragraphs.each { |p| p.each_text_run { |tr| puts tr.text }};
# d.paragraphs.each { |p| p.each_text_run { |tr| puts tr.substitute('A', 'B') }};
# d.save('out.docx')
# lowriter --convert-to pdf [in path]

class Main < Sinatra::Base
    

end
