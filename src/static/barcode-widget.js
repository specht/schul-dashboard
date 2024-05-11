class BarcodeWidget {
    constructor(options) {
        this.beep0 = new Audio('/beep0.mp3');
        this.beep1 = new Audio('/beep1.mp3');
        this.beep2 = new Audio('/beep2.mp3');

        this.element = options.element;
        let container = $("<div class='_barcode_widget' style='border: 1px solid #ddd; padding: 15px; border-radius: 15px; box-shadow: 0px 0px 5px rgba(0,0,0,0.2); margin-bottom: 15px; background-color: #eee;'>");
        let video_container = $("<div style='position: relative; width: 100%; overflow: hidden; height: 200px; margin-bottom: 15px; display: none;'>");
        let video = $("<video class='rounded shadow' style='object-fit: cover; position: absolute; left: 0; top: 0; width: 100%; height: 100%;'>");
        let expand_link = $(`<a href=''>`).text('eingeben');
        let hint = $("<div class='text-muted text-sm'>").text(teacher_logged_in ? 'Alternativ können Sie den Barcode auch ' : 'Alternativ kannst du den Barcode auch ').append(expand_link).append('.');
        if (station_logged_in)
            hint = $("<div class='text-muted text-sm'>").text('Barcode:');
        let input_group = $("<div class='input-group mt-1'>").hide();
        let text_input = $("<input type='text' class='form-control' style='text-align: center'>");
        let submit_button = $("<button class='btn btn-success' type='button'>").text('Senden');
        expand_link.click(function(e) {
            e.preventDefault();
            input_group.slideDown();
            text_input.focus();
        });
        input_group.append(text_input);
        input_group.append($("<div class='input-group-append'>").append(submit_button));
        video_container.append(video);
        container.append(video_container);
        container.append(hint);
        container.append(input_group);
        this.checksum_hint = $(`<div style='display: none;' class='text-sm mt-3'>`).html(`<span class='text-danger'>Hinweis:</span> Dieses Exemplar hat eine Prüfziffer, weshalb der Barcode vom tatsächlichen Exemplar gescannt werden muss.`).appendTo(container);
        this.checksum_hint_special_access = $(`<span style='display: none;' class='text-sm mt-3'>`).html(`Da du mit <b>speziellen Rechten</b> angemeldet bist, kannst du &ndash; wenn du dir sicher bist, was du tust &ndash; diese Hürde jedoch umgehen, indem du die folgende Prüfsumme einfach an den Barcode anhängst: <span class='_checksum_here' style='font-weight: bold; font-family: monospace;'></span>`).appendTo(this.checksum_hint);
        this.element.append(container);
        this.text_input = text_input;
        this.submit_button = submit_button;

        this.last_scanned = null;
        this.disabled = false;

        let hints = null;
        if (options.formats) {
            let hints = new Map();
            let formats = options.formats;
            hints.set(ZXing.DecodeHintType.POSSIBLE_FORMATS, formats);
        }
        this.on_scan = options.on_scan;
        if (!station_logged_in) {
            let codeReader = new ZXing.BrowserMultiFormatReader(hints);
            let no_camera = false;
            codeReader.decodeFromVideoDevice(null, video[0], (result, err) => {
                if (result) {
                    this._on_scan(result.text, true);
                }
            }).catch(e => {
                no_camera = true;
                hint.text(teacher_logged_in ?
                    'Es konnte keine Kamera erkannt werden. Versuchen Sie es bitte mit einem anderen Gerät oder geben Sie den Barcode manuell ein:' :
                    'Es konnte keine Kamera erkannt werden. Versuch es bitte mit einem anderen Gerät oder gib den Barcode manuell ein:');
                input_group.show();
                $(document).keydown(function(e) {
                    if (e.key === 'F8') {
                        console.log(e);
                        text_input.focus();
                        text_input.val('');
                        e.preventDefault();
                    }
                });
            }).finally(function() {
                if (!no_camera)
                    video_container.show();
            });
        } else {
            // hint.text('Es konnte keine Kamera erkannt werden. Versuch es bitte mit einem anderen Gerät oder gib den Barcode manuell ein:');
            input_group.show();
            $(document).keydown(function(e) {
                if (e.key === 'F8') {
                    console.log(e);
                    text_input.focus();
                    text_input.val('');
                    e.preventDefault();
                }
            });
        }

        let self = this;
        submit_button.click(function() {
            let s = text_input.val().trim();
            if (s.length > 0) self._on_scan(s, false);
        });

        text_input.keydown(function(e) {
            if (e.key === 'Enter') {
                submit_button.click();
            }
        })
    }

    _on_scan(s, scanned) {
        if (this.disabled)
            return;
        if (scanned) {
            if (s !== this.last_scanned) {
                sound.play('scan');
                this.last_scanned = s;
                this.text_input.val(s);
                this.on_scan(s, true);
            }
        } else {
            this.on_scan(s, false);
            this.text_input.focus();
        }
    }

    disable() {
        this.text_input.prop('disabled', true);
        this.submit_button.prop('disabled', true);
        this.disabled = true;
    }

    handle_error(data) {
        this.checksum_hint.slideUp();
        this.checksum_hint_special_access.slideUp();
        if (data.error) {
            console.log(data.error);
            if (data.error.indexOf('checksum_required_but_absent') === 0) {
                this.checksum_hint.slideDown();
                if (data.error.indexOf('checksum_required_but_absent [') === 0) {
                    let checksum = data.error.match(/\[(\w+)\]/)[1];
                    this.checksum_hint_special_access.slideDown();
                    this.checksum_hint_special_access.find('._checksum_here').text(`-${checksum}`);
                }
            }
        }
    }
}