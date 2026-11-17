# Test stack only: a small stand-in for the design ideas page that
# /api/werkstatt serves from /internal (in production it is copied there by
# hand and is not part of the repository).
File.write('/internal/werkstatt.html', <<~END_OF_HTML)
    <!doctype html>
    <html lang="de">
    <head><meta charset="utf-8"><title>Werkstatt (Beispiel)</title></head>
    <body><p>Beispielseite für die Tests</p></body>
    </html>
END_OF_HTML
