var editor = null;
var term = null;
var fitAddon = null;
var process_running = false;
var ws = null;
var input = null;
var message_queue = [];
var shown_passed_modal = false;
window.interval = null;
window.message_to_append = null;
window.message_to_append_index = 0;
window.message_to_append_timestamp = 0.0;

var CLING_COLORS = {"daffodil-100":"#262203","daffodil-200":"#413a05","daffodil-300":"#72670a","daffodil-400":"#b3a110","daffodil-500":"#ffe617","daffodil-600":"#ffeb45","daffodil-700":"#fff073","daffodil-800":"#fff5a2","daffodil-900":"#fffad0","daisy-100":"#251f04","daisy-200":"#403607","daisy-300":"#705f0c","daisy-400":"#af9413","daisy-500":"#fad31c","daisy-600":"#fbdb49","daisy-700":"#fce476","daisy-800":"#fdeda4","daisy-900":"#fef6d1","mustard-100":"#251b03","mustard-200":"#402e05","mustard-300":"#71520a","mustard-400":"#b18010","mustard-500":"#fdb717","mustard-600":"#fdc545","mustard-700":"#fdd373","mustard-800":"#fee2a2","mustard-900":"#fef0d0","circus-zest-100":"#251904","circus-zest-200":"#402b08","circus-zest-300":"#704c0e","circus-zest-400":"#af7717","circus-zest-500":"#faaa21","circus-zest-600":"#fbbb4d","circus-zest-700":"#fccc79","circus-zest-800":"#fddda6","circus-zest-900":"#feeed2","pumpkin-100":"#241109","pumpkin-200":"#3d1d10","pumpkin-300":"#6c341c","pumpkin-400":"#a9522c","pumpkin-500":"#f1753f","pumpkin-600":"#f39065","pumpkin-700":"#f6ac8b","pumpkin-800":"#f9c7b2","pumpkin-900":"#fce3d8","tangerine-100":"#230d05","tangerine-200":"#3c1609","tangerine-300":"#6a2710","tangerine-400":"#a63d19","tangerine-500":"#ed5724","tangerine-600":"#f0784f","tangerine-700":"#f49a7b","tangerine-800":"#f7bba7","tangerine-900":"#fbddd3","salmon-100":"#230a08","salmon-200":"#3d110e","salmon-300":"#6b1f19","salmon-400":"#a73027","salmon-500":"#ef4538","salmon-600":"#f26a5f","salmon-700":"#f58f87","salmon-800":"#f8b4af","salmon-900":"#fbd9d7","persimmon-100":"#230607","persimmon-200":"#3b0a0c","persimmon-300":"#691215","persimmon-400":"#a41c21","persimmon-500":"#ea2830","persimmon-600":"#ee5359","persimmon-700":"#f27e82","persimmon-800":"#f6a9ac","persimmon-900":"#fad4d5","rouge-100":"#1c0505","rouge-200":"#300809","rouge-300":"#540f11","rouge-400":"#83181a","rouge-500":"#bc2326","rouge-600":"#c94f51","rouge-700":"#d67b7c","rouge-800":"#e4a7a8","rouge-900":"#f1d3d3","scarlet-100":"#150100","scarlet-200":"#230300","scarlet-300":"#3f0501","scarlet-400":"#620802","scarlet-500":"#8c0c03","scarlet-600":"#a33c35","scarlet-700":"#ba6d67","scarlet-800":"#d19d9a","scarlet-900":"#e8cecc","hot-pink-100":"#22030d","hot-pink-200":"#3a0617","hot-pink-300":"#670a29","hot-pink-400":"#a01041","hot-pink-500":"#e5185d","hot-pink-600":"#ea467d","hot-pink-700":"#ef749d","hot-pink-800":"#f4a2be","hot-pink-900":"#f9d0de","princess-100":"#24131a","princess-200":"#3e212c","princess-300":"#6d3b4e","princess-400":"#aa5c7a","princess-500":"#f384ae","princess-600":"#f59cbe","princess-700":"#f7b5ce","princess-800":"#facdde","princess-900":"#fce6ee","petal-100":"#251d1f","petal-200":"#403235","petal-300":"#70595e","petal-400":"#af8b93","petal-500":"#fac6d2","petal-600":"#fbd1db","petal-700":"#fcdce4","petal-800":"#fde8ed","petal-900":"#fef3f6","lilac-100":"#1a161d","lilac-200":"#2d2632","lilac-300":"#504359","lilac-400":"#7c698b","lilac-500":"#b296c7","lilac-600":"#c1abd2","lilac-700":"#d0c0dd","lilac-800":"#e0d5e8","lilac-900":"#efeaf3","lavender-100":"#120f1a","lavender-200":"#1f1a2c","lavender-300":"#372e4e","lavender-400":"#56487a","lavender-500":"#7b67ae","lavender-600":"#9585be","lavender-700":"#afa3ce","lavender-800":"#cac2de","lavender-900":"#e4e0ee","violet-100":"#0e0711","violet-200":"#180d1e","violet-300":"#2a1735","violet-400":"#422553","violet-500":"#5f3577","violet-600":"#7f5d92","violet-700":"#9f85ad","violet-800":"#bfaec8","violet-900":"#dfd6e3","ceadon-100":"#1c1f14","ceadon-200":"#313523","ceadon-300":"#565e3e","ceadon-400":"#879260","ceadon-500":"#c1d18a","ceadon-600":"#cddaa1","ceadon-700":"#d9e3b8","ceadon-800":"#e6ecd0","ceadon-900":"#f2f5e7","olive-100":"#12150c","olive-200":"#1f2515","olive-300":"#364126","olive-400":"#54653b","olive-500":"#799155","olive-600":"#93a777","olive-700":"#aebd99","olive-800":"#c9d3bb","olive-900":"#e4e9dd","bamboo-100":"#131c09","bamboo-200":"#203010","bamboo-300":"#39541d","bamboo-400":"#59832e","bamboo-500":"#80bc42","bamboo-600":"#99c967","bamboo-700":"#b2d68d","bamboo-800":"#cce4b3","bamboo-900":"#e5f1d9","grass-100":"#0b1809","grass-200":"#122910","grass-300":"#21481c","grass-400":"#33702c","grass-500":"#4aa03f","grass-600":"#6eb365","grass-700":"#92c68b","grass-800":"#b6d9b2","grass-900":"#daecd8","kelly-100":"#03140b","kelly-200":"#052212","kelly-300":"#093d21","kelly-400":"#0f5f33","kelly-500":"#16884a","kelly-600":"#449f6e","kelly-700":"#73b792","kelly-800":"#a1cfb6","kelly-900":"#d0e7da","forrest-100":"#000906","forrest-200":"#00100b","forrest-300":"#001c14","forrest-400":"#002c20","forrest-500":"#003f2e","forrest-600":"#336557","forrest-700":"#668b81","forrest-800":"#99b2ab","forrest-900":"#ccd8d5","cloud-100":"#1d2124","cloud-200":"#31383d","cloud-300":"#57646c","cloud-400":"#889ba9","cloud-500":"#c3def1","cloud-600":"#cfe4f3","cloud-700":"#dbebf6","cloud-800":"#e7f1f9","cloud-900":"#f3f8fc","dream-100":"#0c1c23","dream-200":"#15303c","dream-300":"#26556a","dream-400":"#3b85a6","dream-500":"#55beed","dream-600":"#77cbf0","dream-700":"#99d8f4","dream-800":"#bbe5f7","dream-900":"#ddf2fb","gulf-100":"#071921","gulf-200":"#0c2b39","gulf-300":"#164b64","gulf-400":"#22759d","gulf-500":"#31a8e0","gulf-600":"#5ab9e6","gulf-700":"#83caec","gulf-800":"#acdcf2","gulf-900":"#d5edf8","turquoise-100":"#05141e","turquoise-200":"#082334","turquoise-300":"#0f3e5b","turquoise-400":"#18608f","turquoise-500":"#238acc","turquoise-600":"#4fa1d6","turquoise-700":"#7bb8e0","turquoise-800":"#a7d0ea","turquoise-900":"#d3e7f4","sky-100":"#010e1a","sky-200":"#03182c","sky-300":"#052b4e","sky-400":"#09437a","sky-500":"#0d60ae","sky-600":"#3d7fbe","sky-700":"#6d9fce","sky-800":"#9ebfde","sky-900":"#cedfee","indigo-100":"#030814","indigo-200":"#050f22","indigo-300":"#091a3c","indigo-400":"#0e295e","indigo-500":"#143b86","indigo-600":"#43629e","indigo-700":"#7289b6","indigo-800":"#a1b0ce","indigo-900":"#d0d7e6","navy-100":"#00040b","navy-200":"#000612","navy-300":"#000c21","navy-400":"#001233","navy-500":"#001b4a","navy-600":"#33486e","navy-700":"#667692","navy-800":"#99a3b6","navy-900":"#ccd1da","sea-foam-100":"#121e1d","sea-foam-200":"#203431","sea-foam-300":"#385c57","sea-foam-400":"#578f88","sea-foam-500":"#7dcdc2","sea-foam-600":"#97d7ce","sea-foam-700":"#b1e1da","sea-foam-800":"#cbebe6","sea-foam-900":"#e5f5f2","teal-100":"#001919","teal-200":"#002b2b","teal-300":"#004b4b","teal-400":"#007575","teal-500":"#00a8a8","teal-600":"#33b9b9","teal-700":"#66caca","teal-800":"#99dcdc","teal-900":"#cceded","peacock-100":"#021617","peacock-200":"#042628","peacock-300":"#084347","peacock-400":"#0c686f","peacock-500":"#12959f","peacock-600":"#41aab2","peacock-700":"#70bfc5","peacock-800":"#a0d4d8","peacock-900":"#cfe9eb","cyan-100":"#010b0c","cyan-200":"#021315","cyan-300":"#042325","cyan-400":"#06363a","cyan-500":"#094e54","cyan-600":"#3a7176","cyan-700":"#6b9498","cyan-800":"#9cb8ba","cyan-900":"#cddbdc","chocolate-100":"#080402","chocolate-200":"#0e0704","chocolate-300":"#190d07","chocolate-400":"#27150b","chocolate-500":"#381e11","chocolate-600":"#5f4b40","chocolate-700":"#877870","chocolate-800":"#afa59f","chocolate-900":"#d7d2cf","terra-cotta-100":"#1c0d04","terra-cotta-200":"#311708","terra-cotta-300":"#56290e","terra-cotta-400":"#864016","terra-cotta-500":"#c05c20","terra-cotta-600":"#cc7c4c","terra-cotta-700":"#d99d79","terra-cotta-800":"#e5bda5","terra-cotta-900":"#f2ded2","camel-100":"#1c1710","camel-200":"#30271b","camel-300":"#564530","camel-400":"#866c4b","camel-500":"#bf9b6b","camel-600":"#cbaf88","camel-700":"#d8c3a6","camel-800":"#e5d7c3","camel-900":"#f2ebe1","linen-100":"#221f19","linen-200":"#3b362a","linen-300":"#685f4b","linen-400":"#a39475","linen-500":"#e9d4a7","linen-600":"#eddcb8","linen-700":"#f1e5ca","linen-800":"#f6eddb","linen-900":"#faf6ed","stone-100":"#222221","stone-200":"#3b3a39","stone-300":"#686765","stone-400":"#a2a19d","stone-500":"#e7e6e1","stone-600":"#ebebe7","stone-700":"#f0f0ed","stone-800":"#f5f5f3","stone-900":"#fafaf9","smoke-100":"#1f1f1f","smoke-200":"#353535","smoke-300":"#5d5d5e","smoke-400":"#919293","smoke-500":"#cfd0d2","smoke-600":"#d8d9db","smoke-700":"#e2e2e4","smoke-800":"#ebeced","smoke-900":"#f5f5f6","steel-100":"#141415","steel-200":"#232324","steel-300":"#3e3e40","steel-400":"#606164","steel-500":"#8a8b8f","steel-600":"#a1a2a5","steel-700":"#b8b9bb","steel-800":"#d0d0d2","steel-900":"#e7e7e8","slate-100":"#111315","slate-200":"#1e2224","slate-300":"#353b40","slate-400":"#535d65","slate-500":"#778590","slate-600":"#929da6","slate-700":"#adb5bc","slate-800":"#c8ced2","slate-900":"#e3e6e8","charcoal-100":"#0a0b0b","charcoal-200":"#121313","charcoal-300":"#1f2222","charcoal-400":"#313636","charcoal-500":"#474d4d","charcoal-600":"#6b7070","charcoal-700":"#909494","charcoal-800":"#b5b7b7","charcoal-900":"#dadbdb","black-100":"#000001","black-200":"#010102","black-300":"#020203","black-400":"#030405","black-500":"#050608","black-600":"#373739","black-700":"#69696a","black-800":"#9b9b9c","black-900":"#cdcdcd","white-100":"#262626","white-200":"#414141","white-300":"#727272","white-400":"#b3b3b3","white-500":"#ffffff","white-600":"#ffffff","white-700":"#ffffff","white-800":"#ffffff","white-900":"#ffffff"};

jQuery.extend({
    getQueryParameters: function (str) {
        return (str || document.location.search).replace(/(^\?)/, '').split("&").map(function (n) {
            return n = n.split("="), this[n[0]] = n[1], this
        }.bind({}))[0];
    }
});

function show_error_message(message) {
    var div = $('<div>').css('text-align', 'center').css('padding', '15px').addClass('bg-light text-danger').html(message);
    $('.api_messages').empty();
    let button = $("<button class='text-stone-400 btn pull-right form-control' style='width: unset; margin: 8px;' ><i class='fa fa-times'></i></button>");
    $('.api_messages').append(button).append(div).show();
    button.click(function(e) { $('.api_messages').hide(); });
}

function show_success_message(message) {
    var div = $('<div>').css('text-align', 'center').css('padding', '15px').addClass('bg-light text-success').html(message);
    $('.api_messages').empty();
    $('.api_messages').append(div).show();
}

function api_call(url, data, callback, options) {
    if (typeof (options) === 'undefined')
        options = {};

    if (typeof (window.please_wait_timeout) !== 'undefined')
        clearTimeout(window.please_wait_timeout);

    if (options.no_please_wait !== true) {
        // show 'please wait' message after 500 ms
        (function () {
            window.please_wait_timeout = setTimeout(function () {
                var div = $('<div>').css('text-align', 'center').css('padding', '15px').addClass('text-muted').html("<i class='fa fa-cog fa-spin'></i>&nbsp;&nbsp;Einen Moment bitte...");
                $('.api_messages').empty().show();
                $('.api_messages').append(div);
            }, 500);
        })();
    }

    if (typeof(data) !== 'string')
        data = JSON.stringify(data);

    let conf = {
        url: url,
        data: data,
        contentType: 'application/json',
        dataType: 'json',
    };
    if (typeof (options.headers) !== 'undefined') {
        conf.beforeSend = function (xhr) {
            for (let key in options.headers)
                xhr.setRequestHeader(key, options.headers[key]);
        };
    }
    let jqxhr = jQuery.post(conf);

    jqxhr.done(function (data) {
        clearTimeout(window.please_wait_timeout);
        $('.api_messages').empty().hide();
        if (typeof (callback) !== 'undefined') {
            data.success = true;
            callback(data);
        }
    });

    jqxhr.fail(function (http) {
        clearTimeout(window.please_wait_timeout);
        $('.api_messages').empty();
        show_error_message('Bei der Bearbeitung der Anfrage ist ein Fehler aufgetreten.');
        if (typeof (callback) !== 'undefined') {
            var error_message = 'unknown_error';
            try {
                error_message = JSON.parse(http.responseText)['error'];
            } catch (err) {
            }
            console.log(error_message);
            callback({ success: false, error: error_message });
        }
    });
}

function agr_api_call(url, data, callback, options) {
    let data_json = JSON.stringify(data);
    api_call('/api/get_agr_jwt_token', { url: url, payload: data_json }, function (data) {
        if (data.success) {
            let token = data.token;
            let headers = {headers: {'X-JWT': token}};
            api_call(AGR_HOST + url, data_json, callback, { ...options, ...headers });
        } else {
            show_error_message(data.error);
        }
    });
}

function bib_api_call(url, data, callback, options) {
    let data_json = JSON.stringify(data);
    let expired = localStorage.getItem('bib_jwt_expired') || 0;
    if (Date.now() > expired) {
        // request new JWT
        api_call('/api/get_bib_jwt_token', {}, function (data) {
            if (data.success) {
                localStorage.setItem('bib_jwt_token', data.token);
                localStorage.setItem('bib_jwt_expired', Date.now() + data.ttl * 1000);
                let headers = {headers: {'X-JWT': data.token}};
                api_call(BIB_HOST + url, data_json, callback, { ...options, ...headers });
            } else {
                show_error_message(data.error);
            }
        });
    } else {
        // re-use existing JWT
        let headers = {headers: {'X-JWT': localStorage.getItem('bib_jwt_token')}};
        api_call(BIB_HOST + url, data_json, callback, { ...options, ...headers });
    }
}

function perform_logout() {
    api_call('/api/logout', {}, function (data) {
        if (data.success)
            window.location.href = '/';
    });
}

function teletype() {
    var messages = $('#messages');
    var div = messages.children().last();
    var t = Date.now() / 1000.0;
    while ((window.message_to_append_index < window.message_to_append.length) && window.message_to_append_index < (t - window.message_to_append_timestamp) * window.rate_limit) {
        var c = document.createTextNode(window.message_to_append.charAt(window.message_to_append_index));
        div.append(c);
        window.message_to_append_index += 1;
    }
    if (window.message_to_append_index >= window.message_to_append.length) {
        clearInterval(window.interval);
        window.interval = null;
        window.message_to_append = null;
        if (message_queue.length > 0)
            setTimeout(handle_message, 0);
    }
    $("html, body").stop().animate({ scrollTop: $(document).height() }, 0);
}

function handle_message() {
    if (message_queue.length === 0 || window.interval !== null || window.message_to_append !== null)
        return;
    var message = message_queue[0];
    message_queue = message_queue.slice(1);
    which = message.which;
    msg = message.msg;
    timestamp = message.timestamp;
    var messages = $('#messages');
    var div = messages.children().last();
    if ((which === 'note') || (which === 'error') || (!div.hasClass(which))) {
        div = $('<div>').addClass('message ' + which);
        messages.append(div);
        $('<div>').addClass('timestamp').html(timestamp).appendTo(div);
        if (which === 'server' || which == 'client')
            $('<div>').addClass('tick').appendTo(div);
    }
    if (which === 'server' || which === 'client') {
        window.message_to_append = msg;
        if (which === 'client')
            window.message_to_append += "\n";
        window.message_to_append_timestamp = Date.now() / 1000.0;
        window.message_to_append_index = 0;
        var d = 1000 / window.rate_limit;
        if (d < 1)
            d = 1;
        console.log(d);
        window.interval = setInterval(teletype, d);
    }
    else {
        div.append(document.createTextNode(msg));
        div.append("<br />");
        if (message_queue.length > 0)
            setTimeout(handle_message, 0);
    }

    $("html, body").stop().animate({ scrollTop: $(document).height() }, 400);
}

function append(which, msg) {
    var d = new Date();
    var timestamp = ('0' + d.getHours()).slice(-2) + ':' +
        ('0' + d.getMinutes()).slice(-2) + ':' +
        ('0' + d.getSeconds()).slice(-2);
    message_queue.push({ which: which, timestamp: timestamp, msg: msg });
    if (message_queue.length === 1)
        setTimeout(handle_message, 0);
}

function append_client(msg) {
    append('client', msg);
}

function append_server(msg) {
    append('server', msg);
}

function append_note(msg) {
    append('note', msg);
}

function append_error(msg) {
    append('error', msg);
}

Date.prototype.getWeek = function () {
    var date = new Date(this.getTime());
    date.setHours(0, 0, 0, 0);
    // Thursday in current week decides the year.
    date.setDate(date.getDate() + 3 - (date.getDay() + 6) % 7);
    // January 4 is always in week 1.
    var week1 = new Date(date.getFullYear(), 0, 4);
    // Adjust to Thursday in week 1 and count number of weeks from date to week1.
    return 1 + Math.round(((date.getTime() - week1.getTime()) / 86400000
        - 3 + (week1.getDay() + 6) % 7) / 7);
}

function duration_to_str(duration) {
    let min = '' + Math.floor(duration / 60);
    let sec = '' + Math.floor(duration - min * 60);
    if (sec.length < 2)
        sec = '0' + sec;
    return min + ':' + sec;
}

function create_audio_player(from, tag, duration) {
    let player = $('<div>').addClass('audio-player');
    let top = $('<div>').addClass('player-top').appendTo(player);
    let icon = $('<i>').addClass('fa').addClass('fa-play');
    let play_button = $('<button>').addClass('player-button').addClass('btn').addClass('btn-primary').addClass('btn-sm').append(icon).append("&#8203;");
    top.append($('<span>').addClass('player-from').html(from));
    top.append(play_button);
    let seek = $('<div>').addClass('player-seek').appendTo(player);
    let progress = $('<div>').addClass('player-progress').appendTo(seek);
    top.append(play_button);
    let indicator_container = $('<div>').addClass('player-indicator-container').appendTo(progress);
    let indicator = $('<div>').addClass('player-indicator').appendTo(indicator_container);
    indicator.css('left', '0%');
    let duration_div = $('<div>').addClass('player-duration').html(duration_to_str(duration)).appendTo(player);
    let url = '/raw/uploads/audio_comment/' + tag.substr(0, 2) + '/' + tag.substr(2, tag.length - 2) + '.ogg';
    (function (url, duration, button, icon, indicator, duration_div, seek) {
        function activate() {
            if (pb_url !== url) {
                if (pb_url !== null) {
                    pb_audio.currentTime = 0;
                }
                pb_widget = { button: button, icon: icon, indicator: indicator, duration_div: duration_div };
                pb_duration = duration;
                pb_url = url;
                pb_audio.src = url;
            }
        }

        seek.mousedown(function (e) {
            if (url == pb_url) {
                pb_audio.currentTime = pb_duration * e.offsetX / seek.width();
            } else {
                pb_audio.pause();
                pb_audio.currentTime = 0;
                setTimeout(function () {
                    activate();
                    pb_audio.currentTime = pb_duration * e.offsetX / seek.width();
                }, 0);
            }
        });
        button.click(function (e) {
            if (url == pb_url) {
                if (!pb_playing) {
                    activate();
                    pb_audio.play();
                } else {
                    pb_audio.pause();
                }
            } else {
                pb_audio.pause();
                pb_audio.currentTime = 0;
                setTimeout(function () {
                    activate();
                    pb_audio.play();
                }, 0);
            }
        });
    })(url, duration, play_button, icon, indicator, duration_div, seek);
    if (pb_audio === null) {
        pb_audio = document.createElement('audio');
        pb_audio.controls = false;
        pb_audio.addEventListener('play', function (e) {
            pb_playing = true;
            pb_widget.icon.removeClass('fa-play').addClass('fa-pause');
        });
        pb_audio.addEventListener('ended', function () {
            pb_audio.currentTime = 0;
            pb_widget.indicator.css('left', '0%');
            pb_widget.button.find('.fa').removeClass('fa-pause').addClass('fa-play');
            pb_widget.duration_div.html(duration_to_str(pb_duration));
        });
        pb_audio.addEventListener('pause', function () {
            pb_playing = false;
            pb_widget.button.find('.fa').removeClass('fa-pause').addClass('fa-play');
        });
        pb_audio.addEventListener('timeupdate', function (e) {
            pb_widget.indicator.css('left', '' + (100.0 * pb_audio.currentTime / pb_duration) + '%');
            if (pb_audio.currentTime > 0)
                pb_widget.duration_div.html(duration_to_str(pb_audio.currentTime));
        });
    }
    return player;
}

function filter_events_by_timestamp(events, now) {
    let filtered = [];
    for (event of events) {
        if (event.timestamp <= now)
            filtered.push(event);
    }
    return (filtered.length === 0) ? null : filtered;
}


function load_recipients(id, callback, also_load_ext_users, sus_only) {
    let antikenfahrt_recipients = window.antikenfahrt_recipients;
    if (typeof (antikenfahrt_recipients) === 'undefined')
        antikenfahrt_recipients = { recipients: {}, groups: [] };
    if (typeof (also_load_ext_users) === 'undefined' || also_load_ext_users === null)
        also_load_ext_users = { groups: [], recipients: {}, order: [] };
    if (typeof (can_handle_external_users) === 'undefined')
        can_handle_external_users = false;
    if (typeof (sus_only) === 'undefined')
        sus_only = false;
    let uri = '/gen/w/' + id + '/recipients.json.gz';
    var oReq = new XMLHttpRequest();
    oReq.open('GET', uri, true);
    oReq.responseType = 'arraybuffer';

    oReq.onload = function (e) {
        if (e.target.status === 200) {
            let data = pako.ungzip(oReq.response);
            let bb = new Blob([new Uint8Array(data)]);
            let f = new FileReader();
            f.onload = function (e) {
                let entries = JSON.parse(e.target.result);
                for (let group of antikenfahrt_recipients.groups) {
                    if (CAN_HANDLE_EXTERNAL_USERS == false && antikenfahrt_recipients.recipients[group].external === true)
                        continue;
                    entries.groups.push(group);
                    entries.recipients[group] = antikenfahrt_recipients.recipients[group];
                }
                if (sus_only) {
                    entries.groups = [];
                    let new_recipients = {};
                    for (let key in entries.recipients) {
                        if (key.charAt(0) != '/' && (entries.recipients[key].teacher || false) === false) {
                            new_recipients[key] = entries.recipients[key];
                        }
                    }
                    entries.recipients = new_recipients;
                }
                // console.log(entries);
                for (let group of also_load_ext_users.groups)
                    entries.groups.push(group);
                for (let key in also_load_ext_users.recipients) {
                    if (!(key in entries.recipients)) {
                        entries.recipients[key] = {
                            label: also_load_ext_users.recipients[key].label + ' (extern)',
                            external: true
                        };
                        if (typeof (also_load_ext_users.recipients[key].entries) !== 'undefined') {
                            entries.recipients[key].entries = also_load_ext_users.recipients[key].entries;
                        }
                    }
                }
                recipients = entries.recipients;
                recipients_cache = { index: {}, keys: [], index_for_key: {} };
                recipients_cache.groups = entries.groups;
                for (let key of Object.keys(entries.recipients)) {
                    let label = entries.recipients[key].label.trim().toLowerCase();
                    for (let word of label.split(/\s+/)) {
                        word = word.trim();
                        let index = label.lastIndexOf(word);
                        for (let l = 1; l <= word.length; l++) {
                            let span = word.substr(0, l);
                            if (typeof (recipients_cache.index[span]) === 'undefined')
                                recipients_cache.index[span] = {};
                            if (typeof (recipients_cache.index_for_key[key]) === 'undefined') {
                                recipients_cache.index_for_key[key] = recipients_cache.keys.length;
                                recipients_cache.keys.push(key);
                            }
                            recipients_cache.index[span][recipients_cache.index_for_key[key]] = index + l;
                        }
                    }
                }
                delete recipients_cache.index_for_key;
                callback();
            };
            f.readAsText(bb);
        }
    };
    oReq.send();
}

function fix_bad_html(e) {
    for (let attr of ['style', 'face']) {
        $.each(e.find(`[${attr}]`), function (_, x) {
            $(x).removeAttr(attr);
        });
    }
    $.each(e.find('style'), function (_, x) {
        $(x).remove();
    });
    return e;
}

function email_field(email) {
    return `<div class='input-group'><input type='text' class='form-control' readonly value='${email}' style='min-width: 100px;' /><div class='input-group-append'><button class='btn btn-secondary btn-clipboard' data-clipboard-action='copy' title='Eintrag in die Zwischenablage kopieren' data-clipboard-text='${email}'><i class='fa fa-clipboard'></i></button></div></div>`;
}

// receives a string and returns a hash of stem, bnr and optional checksum if valid, null otherwise
function fix_scanned_book_barcode(s) {
    let parts = s.split(/[^\w\d]/);
    if (parts.length < 2)
        return null;
    let stem = parts[0];
    let bnr = parts[1];
    let checksum = parts[2] || null;
    if (!/^\d+$/.test(stem))
        return null;
    if (!/^\d+$/.test(bnr))
        return null;
    if (checksum !== null)
        if (!/^\w\w$/.test(checksum))
            return null;
    return { stem: parseInt(stem), bnr: parseInt(bnr), checksum: checksum };
}

function create_book_div(book, shelf, options = {}) {
    let stem = $(`<span class='text-slate-500 pl-2 pr-1 py-1 absolute text-sm'>`).css('right', '0.5em').text(book.stem);
    if (options.exemplar && options.exemplar.bnr)
        stem.html(`<i class='fa fa-barcode'></i>&nbsp;&nbsp;${book.stem}-${options.exemplar.bnr}`);
    let cover_path = `${BIB_HOST}/gen/covers/${book.stem}-400.jpg`;
    let hover_classes = '';
    if (options.clickable) {
        hover_classes = 'hover:outline hover:outline-1 hover:shadow-lg hover:outline-gray-400 cursor-pointer ';
    }
    let div = $(`<div class="${hover_classes} book border overflow-hidden col-span-12 md:col-span-6 xl:col-span-4 shadow-md bg-white shadow-md rounded" style="overflow-wrap: break-word; position: relative;">`);
    if (options.show_bib_entry) {
        let bib_entry = $(`<div class="text-sm px-2 bg-stone-700 text-stone-300 py-1 relative" style='border-bottom: 1px solid #ddd; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'>`);
        if (!(options.preview)) {
            bib_entry.text(book.bib_entry);
            bib_entry.append(stem);
        }
        else
            bib_entry.html('&nbsp;');
        div.append(bib_entry);
    } else {
        div.append(stem.addClass('rounded bg-white bottom-0'));
    }
    let cover = $(`<div class='bg-stone-800 shadow shadow-md mr-3 border-r-2 relative' style="float: left; height: 200px; width: 145px; background-position: center center; background-size: contain; background-repeat: no-repeat; border-right: 1px solid #ddd; "></div>`);
    if (!(options.preview)) {
        if (book.has_cover) {
            cover.css('background-image', `url(${cover_path})`);
        } else {
            cover.addClass('p-2 text-center italic text-sm');
            cover.append($('<div>').text(book.title).addClass('text-slate-400 pt-3 pb-2'));
            if (book.author) {
                cover.append($('<hr />'));
                cover.append($('<div>').text(book.author).addClass('text-slate-600'));
            }
        }
    }
    div.append(cover);
    if (!(options.preview)) {
        let details = $(`<div class="w-full p-2" style="height: 200px;">`);
        let title_div = $(`<div style="max-height: 60px; overflow: hidden;">`);
        title_div.append($(`<span class="font-bold text-xl">`).text(book.title));
        if (book.subtitle)
            title_div.append($(`<span class='text-lg'>`).text(` – ${book.subtitle}`));
        details.append(title_div);
        if (book.author)
            details.append($(`<div class="font-italic truncate">`).text(book.author));
        let parts = [];
        if (book.verlag)
            parts.push(book.verlag);
        if (book.published)
            parts.push(book.published);
        if (parts.length > 0)
            details.append($(`<div style='white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'>`).text(parts.join(', ')));
        parts = [];
        if (book.page_count)
            parts.push(`${book.page_count} Seiten`);
        if (parts.length > 0)
            details.append($(`<div>`).text(parts.join(', ')));
        let discarded_span = '';
        if (options.exemplar && options.exemplar.ts_discarded) {
            let t = moment.unix(options.exemplar.ts_discarded);
            discarded_span = $(`<span class='bg-red-400 text-red-900 px-2 py-1 rounded mr-2'>`).text(`ausgemustert am ${t.format('L')}`);
        }
        let shelf_span = '';
        if (typeof(shelf) !== 'undefined' && shelf !== null) {
            console.log(shelf);
            shelf_span = $(`<span class='bg-violet-700 px-2 py-1 rounded mr-2 font-bold'>`).text(shelf.location);
        }

        let available_count = $(`<span class='bg-sky-800 px-2 py-1 rounded mr-2 font-bold'>`).text(`${book.bib_available} / ${book.bib_count}`);
        let ausleih_count = $(`<span class='bg-bamboo-800 px-2 py-1 rounded mr-2 font-bold'>`).text(book.ausleih_count);
        let isbn = $(`<span>`).text(`ISBN: ${book.isbn}`);
        // let count_div = $('<span>').append(available_count).append(ausleih_count);
        // if (book.ausleih_count != book.bib_count - book.bib_available)
        //     count_div.addClass('bg-red-500 px-1 py-2 rounded');
        let count_div = '';
        details.append($(`<div style='white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'>`).append(discarded_span).append(shelf_span).append(count_div));
        if (book.isbn) {
            details.append($(`<div>`).append(isbn));
        }
        if (book.description) {
            details.append($(`<hr class='my-2'>`));
            details.append($(`<div class="font-italic" style='white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'>`).text(book.description));
        }
        else if (book.text_snippet) {
            details.append($(`<hr class='my-2'>`));
            details.append($(`<div class="font-italic" style='white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'>`).text(book.text_snippet));
        }
        div.append(details);
    }
    if (options.clickable) {
        div.click(function(e) {
            options.callback(book);
        });
    }
    return div;
}

function currency_string_plain(preis) {
    if (preis) {
        let pre = `${Math.floor(preis / 100)}`;
        let post = `${preis % 100}`;
        while (post.length < 2)
            post = '0' + post;
        return `${pre},${post}`;
    } else return null;
}

function currency_string(preis, waehrung) {
    let s = currency_string_plain(preis);
    if (s) {
        return `${s} ${waehrung}`;
    } else {
        return null;
    }
}

