var editor = null;
var term = null;
var fitAddon = null;
var process_running = false;
var ws = null;
var input = null;
var message_queue = [];
var timerId = null;
var shown_passed_modal = false;
window.interval = null;
window.message_to_append = null;
window.message_to_append_index = 0;
window.message_to_append_timestamp = 0.0;

jQuery.extend({
    getQueryParameters : function(str) {
        return (str || document.location.search).replace(/(^\?)/,'').split("&").map(function(n){
            return n = n.split("="), this[n[0]] = n[1], this
        }.bind({}))[0];
    }
});

function show_error_message(message)
{
    var div = $('<div>').css('text-align', 'center').css('padding', '15px').addClass('bg-light text-danger').html(message);
    $('.api_messages').empty();
    $('.api_messages').append(div).show();
}

function show_success_message(message)
{
    var div = $('<div>').css('text-align', 'center').css('padding', '15px').addClass('bg-light text-success').html(message);
    $('.api_messages').empty();
    $('.api_messages').append(div).show();
}

function api_call(url, data, callback, options)
{
    if (typeof(options) === 'undefined')
        options = {};
    
    if (typeof(window.please_wait_timeout) !== 'undefined')
        clearTimeout(window.please_wait_timeout);
    
    if (options.no_please_wait !== true)
    {
        // show 'please wait' message after 500 ms
        (function() {
            window.please_wait_timeout = setTimeout(function() {
                var div = $('<div>').css('text-align', 'center').css('padding', '15px').addClass('text-muted').html("<i class='fa fa-cog fa-spin'></i>&nbsp;&nbsp;Einen Moment bitte...");
                $('.api_messages').empty().show();
                $('.api_messages').append(div);
            }, 500);
        })();
    }
    
    var jqxhr = jQuery.post({
        url: url,
        data: JSON.stringify(data),
        contentType: 'application/json',
        dataType: 'json'
    });
    
    jqxhr.done(function(data) {
        clearTimeout(window.please_wait_timeout);
        $('.api_messages').empty().hide();
        if (typeof(callback) !== 'undefined')
        {
            data.success = true;
            callback(data);
        }
    });
    
    jqxhr.fail(function(http) {
        clearTimeout(window.please_wait_timeout);
        $('.api_messages').empty();
        show_error_message('Bei der Bearbeitung der Anfrage ist ein Fehler aufgetreten.');
        if (typeof(callback) !== 'undefined')
        {
            var error_message = 'unknown_error';
            try {
                error_message = JSON.parse(http.responseText)['error'];
            } catch(err) {
            }
            console.log(error_message);
            callback({success: false, error: error_message});
        }
    });
}

function perform_logout()
{
    api_call('/api/logout', {}, function(data) {
        if (data.success)
            window.location.href = '/';
    });
}

function teletype() {
    var messages = $('#messages');
    var div = messages.children().last();
    var t = Date.now() / 1000.0;
    while ((window.message_to_append_index < window.message_to_append.length) && window.message_to_append_index < (t - window.message_to_append_timestamp) * window.rate_limit)
    {
        var c = document.createTextNode(window.message_to_append.charAt(window.message_to_append_index));
        div.append(c);
        window.message_to_append_index += 1;
    }
    if (window.message_to_append_index >= window.message_to_append.length)
    {
        clearInterval(window.interval);
        window.interval = null;
        window.message_to_append = null;
        if (message_queue.length > 0)
            setTimeout(handle_message, 0);
    }
    $("html, body").stop().animate({ scrollTop: $(document).height() }, 0);
}

function handle_message()
{
    if (message_queue.length === 0 || window.interval !== null || window.message_to_append !== null)
        return;
    var message = message_queue[0];
    message_queue = message_queue.slice(1);
    which = message.which;
    msg = message.msg;
    timestamp = message.timestamp;
    var messages = $('#messages');
    var div = messages.children().last();
    if ((which === 'note') || (which === 'error') || (!div.hasClass(which)))
    {
        div = $('<div>').addClass('message ' + which);
        messages.append(div);
        $('<div>').addClass('timestamp').html(timestamp).appendTo(div);
        if (which === 'server' || which == 'client')
            $('<div>').addClass('tick').appendTo(div);
    }
    if (which === 'server' || which === 'client')
    {
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
    else
    {
        div.append(document.createTextNode(msg));
        div.append("<br />");
        if (message_queue.length > 0)
            setTimeout(handle_message, 0);
    }
    
    $("html, body").stop().animate({ scrollTop: $(document).height() }, 400);
}

function append(which, msg)
{
    var d = new Date();
    var timestamp = ('0' + d.getHours()).slice(-2) + ':' +
                    ('0' + d.getMinutes()).slice(-2) + ':' +
                    ('0' + d.getSeconds()).slice(-2);
    message_queue.push({which: which, timestamp: timestamp, msg: msg});
    if (message_queue.length === 1)
        setTimeout(handle_message, 0);
}

function append_client(msg)
{
    append('client', msg);
}

function append_server(msg)
{
    append('server', msg);
}

function append_note(msg)
{
    append('note', msg);
}

function append_error(msg)
{
    append('error', msg);
}

function keepAlive() { 
    var timeout = 20000;
    if (ws.readyState == ws.OPEN) {  
        ws.send('');  
    }  
    (function() {
        timerId = setTimeout(keepAlive, timeout);  
    })();
}                  

function push_message(s, color, delay) {
    if (typeof(color) === 'undefined')
        color = 'warning';
    $('.info').stop();
    $('.info').removeClass('bg-warning');
    $('.info').removeClass('bg-success');
    $('.info').addClass('bg-' + color);
    $('.info').css('color', 'unset');
    if (color === 'success')
        $('.info').css('color', '#fff');
    $('.info').html(s).slideDown();
    if (delay > 0)
        $('.info').delay(delay).slideUp();
}

function setup_ws(ws)
{
    ws.onopen = function () {
        keepAlive();
        ws.send(JSON.stringify({
            action: 'run', 
            slug: window.slug,
            script: window.launch_this_script
        }));
    }
    
    ws.onclose = function () {
        clearTimeout(timerId);
    }
    
    ws.onmessage = function (msg) {
        data = JSON.parse(msg.data);
        if (data.hello === 'world')
        {
            window.rate_limit = data.rate_limit;
        }
        else if (data.status === 'started')
        {
            $('#run').removeClass('btn-success').addClass('btn-danger').html("<i class='fa fa-stop'></i>&nbsp;&nbsp;Abbrechen").prop('disabled', false);
            process_running = true;
            if (!$('#screen').is(':visible'))
                term.focus();
        }
        else if (data.status === 'stopped')
        {
            $('#run').removeClass('btn-danger').addClass('btn-success').html("<i class='fa fa-play'></i>&nbsp;&nbsp;Ausführen");
            $('#editor').prop('disabled', false);
            process_running = false;
            editor.setReadOnly(false);
            term.write("\r\n");
            term.blur();
            if ($('body').width() >= 768)
                editor.focus();
            $('#screen img.pixelflut').removeAttr('src').attr('src', '/pixelflut/?' + Date.now());
        }
        else if (data.status === 'passed')
        {
            $('#already-solved').show();
            if (!shown_passed_modal)
                $('#passedModal').modal('show');
            shown_passed_modal = true;
            push_message('Herzlichen Glückwunsch, dein Programm ist korrekt!', 'success', 0);
        }
        else if (typeof(data.connection_error) !== 'undefined')
        {
            append_error('Failed connection attempt to ' + data.host + ' ' + (data.tls ? '(TLS) ' : '') + 'on port ' + data.port + ' (' + data.connection_error + ')');
        }
        else if (typeof(data.message) !== 'undefined')
        {
            push_message(data.message, data.color, 0);
        }
        else if (typeof(data.stdout) !== 'undefined')
        {
            term.write(data.stdout);
        }
        else if (typeof(data.stderr) !== 'undefined')
        {
            term.write(data.stderr);
        }
        else if (typeof(data.dungeon) !== 'undefined')
        {
            enqueue_dungeon_command(data.dungeon);
        }
        else if (typeof(data.script_sha1) !== 'undefined')
        {
            history.replaceState({}, null, '/task/' + window.slug + '/' + data.script_sha1); 
        }
    }
}

function sendInput()
{
    var msg = input.val();
    append_client(msg);
    ws.send(JSON.stringify({action: 'send', message: msg}))
    input.val("");
}

function launch_script(script)
{
    $('.info').hide();
    $('#run').prop('disabled', true);
    $('#editor').prop('disabled', true);
    editor.setReadOnly(true);
    var ws_uri = 'ws://' + location.host + '/ws';
    if (location.host !== 'localhost:8020')
        ws_uri = 'wss://' + location.host + '/ws';
    ws = new WebSocket(ws_uri);
    setup_ws(ws);
    window.launch_this_script = script;
    $('.mi-load-latest-draft').removeClass('disabled');
}

function kill_script()
{
    ws.send(JSON.stringify({
        action: 'kill'
    }));
}

Date.prototype.getWeek = function() {
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
    (function(url, duration, button, icon, indicator, duration_div, seek) {
        function activate() {
            if (pb_url !== url) {
                if (pb_url !== null) {
                    pb_audio.currentTime = 0;
                }
                pb_widget = {button: button, icon: icon, indicator: indicator, duration_div: duration_div};
                pb_duration = duration;
                pb_url = url;
                pb_audio.src = url;
            }
        }
        
        seek.mousedown(function(e) {
            if (url == pb_url) {
                pb_audio.currentTime = pb_duration * e.offsetX / seek.width();
            } else {
                pb_audio.pause();
                pb_audio.currentTime = 0;
                setTimeout(function() {
                    activate();
                    pb_audio.currentTime = pb_duration * e.offsetX / seek.width();
                }, 0);
            }
        });
        button.click(function(e) {
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
                setTimeout(function() {
                    activate();
                    pb_audio.play();
                }, 0);
            }
        });
    })(url, duration, play_button, icon, indicator, duration_div, seek);
    if (pb_audio === null) {
        pb_audio = document.createElement('audio');
        pb_audio.controls = false;
        pb_audio.addEventListener('play', function(e) {
            pb_playing = true;
            pb_widget.icon.removeClass('fa-play').addClass('fa-pause');
        });
        pb_audio.addEventListener('ended', function() {
            pb_audio.currentTime = 0;
            pb_widget.indicator.css('left', '0%');
            pb_widget.button.find('.fa').removeClass('fa-pause').addClass('fa-play');
            pb_widget.duration_div.html(duration_to_str(pb_duration));
        });
        pb_audio.addEventListener('pause', function() {
            pb_playing = false;
            pb_widget.button.find('.fa').removeClass('fa-pause').addClass('fa-play');
        });
        pb_audio.addEventListener('timeupdate', function(e) {
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


function load_recipients(id, callback, also_load_ext_users) {
    if (typeof(also_load_ext_users) === 'undefined')
        also_load_ext_users = {groups: [], recipients: {}, order: []};
    let uri = '/gen/w/' + id + '/recipients.json.gz';
    var oReq = new XMLHttpRequest();
    oReq.open('GET', uri, true);
    oReq.responseType = 'arraybuffer';

    oReq.onload = function(e) {
        if (e.target.status === 200) {
            let data = pako.ungzip(oReq.response);
            let bb = new Blob([new Uint8Array(data)]);
            let f = new FileReader();
            f.onload = function(e) {
                let entries = JSON.parse(e.target.result);
                for (let group of also_load_ext_users.groups)
                    entries.groups.push(group);
                for (let key in also_load_ext_users.recipients) {
                    if (!(key in entries.recipients)) {
                        entries.recipients[key] = {
                            label: also_load_ext_users.recipients[key].label + ' (extern)',
                            external: true
                        };
                        if (typeof(also_load_ext_users.recipients[key].entries) !== 'undefined') {
                            entries.recipients[key].entries = also_load_ext_users.recipients[key].entries;
                        }
                    }
                }
                recipients = entries.recipients;
                recipients_cache = {index: {}, keys: [], index_for_key: {}};
                recipients_cache.groups = entries.groups;
                for (let key of Object.keys(entries.recipients)) {
                    let label = entries.recipients[key].label.trim().toLowerCase();
                    for (let word of label.split(/\s+/)) {
                        word = word.trim();
                        let index = label.lastIndexOf(word);
                        for (let l = 1; l <= word.length; l++) {
                            let span = word.substr(0, l);
                            if (typeof(recipients_cache.index[span]) === 'undefined')
                                recipients_cache.index[span] = {};
                            if (typeof(recipients_cache.index_for_key[key]) === 'undefined') {
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
        $.each(e.find(`[${attr}]`), function(_, x) {
            $(x).removeAttr(attr);
        });
    }
    $.each(e.find('style'), function(_, x) {
        $(x).remove();
    });
    return e;
}

function render_katex(e) {
    renderMathInElement(e, {delimiters: [
        {left: "$$", right: "$$", display: true},
        {left: "\\[", right: "\\]", display: true},
        {left: "$", right: "$", display: false},
        {left: "\\(", right: "\\)", display: false}
    ]});
}
