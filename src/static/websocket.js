var ws = null;
var ws_timer_id = null;

function keep_alive() { 
    var timeout = 20000;
    if (ws.readyState == ws.OPEN) {  
        ws.send('');  
    }  
    (function() {
        ws_timer_id = setTimeout(keep_alive, timeout);  
    })();
}                  

function setup_ws(ws)
{
    ws.onopen = function() {
        console.log('ws.onopen');
        keep_alive();
    }
    
    ws.onclose = function() {
        console.log('ws.onclose');
        clearTimeout(ws_timer_id);
        // try to re-establish connection in 10 seconds
        setTimeout(establish_websocket_connection, 10000);
    }
    
    ws.onmessage = function(msg) {
        console.log(msg.data);
        data = JSON.parse(msg.data);
        if (data.command == 'force_reload') {
            window.location.reload();
        } else if (data.command == 'update_monitor_messages') {
            ticker_messages = data.messages;
        }
    }
}

function establish_websocket_connection() {
    var ws_uri = (location.protocol == 'http:' ? 'ws://' : 'wss://') + location.host + '/ws_monitor';
    ws = new WebSocket(ws_uri);
    setup_ws(ws);
}
