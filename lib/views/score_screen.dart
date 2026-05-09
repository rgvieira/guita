import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key});

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  late final WebViewController _controller;
  HttpServer? _server;
  String _filePath = '';
  bool _loaded = false;
  bool _ready = false;
  bool _isPlaying = false;

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final path = ModalRoute.of(context)!.settings.arguments as String;
    if (path != _filePath) {
      _filePath = path;
      _loaded = false;
    }
    if (!_loaded && _filePath.isNotEmpty) {
      _loaded = true;
      _init();
    }
  }

  Future<void> _init() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FlutterChannel', onMessageReceived: _onMsg)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _onReady(),
        onWebResourceError: (e) => debugPrint('WebView error: ${e.description}'),
      ));

    final fontAsset = await rootBundle.load('assets/Bravura.otf');
    final fontBytes = fontAsset.buffer.asUint8List(fontAsset.offsetInBytes, fontAsset.lengthInBytes);
    final jsCode = await rootBundle.loadString('assets/alphaTab.min.js');

    _server = await HttpServer.bind('127.0.0.1', 0);
    final port = _server!.port;
    debugPrint('Local server on port $port');

    _server!.listen((req) async {
      try {
        final path = req.uri.path;
        debugPrint('HTTP ${req.method} $path');
        if (path == '/alphaTab.min.js') {
          req.response.headers.contentType = ContentType('application', 'javascript', charset: 'utf-8');
          req.response.write(jsCode);
        } else if (path.endsWith('.otf')) {
          req.response.headers.contentType = ContentType('font', 'otf');
          req.response.add(fontBytes);
        } else if (path == '/index.html' || path == '/') {
          final html = _buildHtml();
          req.response.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
          req.response.write(html);
        } else {
          req.response.statusCode = 404;
          req.response.write('Not found');
        }
      } catch (e) {
        debugPrint('Server error: $e');
        if (req.response.statusCode == 200) {
          try { req.response.statusCode = 500; req.response.write('Server error'); } catch (_) {}
        }
      } finally {
        await req.response.close();
      }
    });

    await _controller.loadRequest(Uri.parse('http://127.0.0.1:$port/index.html'));
  }

  String _buildHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,user-scalable=no">
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%;height:100%;background:#fff}
#alphaTab{width:100%;height:100%;overflow:auto}
.at-cursors .at-cursor-bar{fill:rgba(255,0,0,0.3)}
.at-cursors .at-cursor-beat{fill:rgba(0,0,255,0.15)}
#status{position:fixed;top:8px;left:8px;z-index:999;font:12px/1.4 sans-serif;color:#666;pointer-events:none}
</style>
</head>
<body>
<div id="status">initializing...</div>
<div id="alphaTab"></div>
<script src="alphaTab.min.js"></script>
<script>
(function(){
  try{
    var el=document.getElementById('alphaTab');
    var st=document.getElementById('status');
    st.textContent='creating api...';
    window.api=new alphaTab.AlphaTabApi(el,{
      staveProfile:1,
      layout:1,
      enablePlayer:true,
      enableCursor:true
    });
    st.textContent='api ready';
    window.api.scoreLoaded.on(function(s){
      st.textContent='score loaded';
      FlutterChannel.postMessage(JSON.stringify({type:'ready'}));
    });
    window.api.playerStateChanged.on(function(s){
      console.log('playerState',s,typeof s,JSON.stringify(s));
      FlutterChannel.postMessage(JSON.stringify({type:'state',state:s}));
    });
    window.api.renderStarted.on(function(){
      st.textContent='rendering...';
    });
    window.api.renderFinished.on(function(){
      st.textContent='rendered';
    });
    window.loadScoreBase64=function(d){
      try{
        st.textContent='decoding...';
        var b=atob(d),u=new Uint8Array(b.length);
        for(var i=0;i<b.length;i++)u[i]=b.charCodeAt(i);
        st.textContent='loading score...';
        window.api.load(u.buffer);
      }catch(e){
        st.textContent='decode error: '+e.message;
        FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'decode: '+e.message}));
      }
    };
    window.playPause=function(){
      try{
        if(!window.api){console.log('api null');return;}
        var r=window.api.playPause();
        if(r&&r.then){
          r.then(function(){console.log('play ok')},function(e){console.log('play reject',e&&e.message);FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'play: '+(e&&e.message)}));});
        }
      }catch(e){
        FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'playPause: '+e.message}));
      }
    };
    window.stop=function(){
      try{window.api.stop()}catch(e){
        FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'stop: '+e.message}));
      }
    };
  }catch(e){
    var st=document.getElementById('status');
    if(st)st.textContent='init error: '+e.message;
    FlutterChannel.postMessage(JSON.stringify({type:'err',msg:e.message}));
  }
})();
window.onerror=function(m,s,l,c,e){
  FlutterChannel.postMessage(JSON.stringify({type:'err',msg:m||'unknown'}));
};
</script>
</body>
</html>
''';
  }

  Future<void> _onReady() async {
    _ready = true;
    await _sendFile();
  }

  Future<void> _sendFile() async {
    if (!_ready) return;
    try {
      final f = File(_filePath);
      if (!await f.exists()) return;
      final bytes = await f.readAsBytes();
      final b64 = base64Encode(bytes);
      await _controller.runJavaScript('loadScoreBase64("$b64");');
    } catch (e) {
      debugPrint('sendFile error: $e');
    }
  }

  void _onMsg(JavaScriptMessage msg) {
    try {
      final d = jsonDecode(msg.message) as Map<String, dynamic>;
      final type = d['type'] as String?;
      debugPrint('onMsg: $type ${msg.message}');
      switch (type) {
        case 'state':
          final state = d['state'];
          debugPrint('state value: $state (${state.runtimeType})');
          setState(() => _isPlaying = state == 1);
        case 'err':
          debugPrint('alphaTab err: ${d['msg']}');
      }
    } catch (e) {
      debugPrint('onMsg parse error: $e');
    }
  }

  Future<void> _togglePlayback() async {
    await _controller.runJavaScript('playPause();');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _filePath.split('\\').last.split('/').last,
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.pushNamed(context, '/practice', arguments: _filePath),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => _controller.runJavaScript('stop();'),
                ),
                const SizedBox(width: 16),
                FloatingActionButton(
                  mini: true,
                  onPressed: _togglePlayback,
                  backgroundColor: _isPlaying ? Colors.red : Colors.brown,
                  child: Icon(
                    _isPlaying ? Icons.stop : Icons.play_arrow,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => _controller.runJavaScript('stop();'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
