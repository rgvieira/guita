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
  late final List<int> _sfBytes;
  int _playerState = 0;
  bool _sfLoaded = false;
  bool _jsReady = false;

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
    final sfAsset = await rootBundle.load('assets/soundfonts/sonivox.sf2');
    _sfBytes = sfAsset.buffer.asUint8List(sfAsset.offsetInBytes, sfAsset.lengthInBytes);

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
        } else if (path == '/sonivox.sf2') {
          req.response.headers.contentType = ContentType('application', 'octet-stream');
          req.response.add(_sfBytes);
        } else if (path == '/index.html' || path == '/') {
          final html = _buildHtml();
          req.response.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
          req.response.write(html);
        } else if (path == '/score') {
          final f = File(_filePath);
          if (await f.exists()) {
            final ext = _filePath.split('.').last.toLowerCase();
            final ct = _mimeForExt(ext);
            req.response.headers.contentType = ContentType.parse(ct);
            req.response.add(await f.readAsBytes());
          } else {
            req.response.statusCode = 404;
            req.response.write('Score not found');
          }
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

  String _mimeForExt(String ext) {
    switch (ext) {
      case 'gp3': return 'application/x-guitar-pro';
      case 'gp4': return 'application/x-guitar-pro';
      case 'gp5': return 'application/x-guitar-pro';
      case 'gpx': return 'application/x-guitar-pro';
      case 'xml': return 'application/xml';
      case 'mxl': return 'application/vnd.recordare.musicxml';
      case 'cap': return 'application/x-capla';
      case 'capx': return 'application/x-capla';
      default:   return 'application/octet-stream';
    }
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
<script>
(function(){
  var OrigAC=window.AudioContext||window.webkitAudioContext;
  window.__audioCtx=null;
  window.AudioContext=function(){
    if(!window.__audioCtx)window.__audioCtx=new OrigAC();
    return window.__audioCtx;
  };
  window.webkitAudioContext=window.AudioContext;
})();
</script>
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
    st.textContent='loading soundfont...';

    window.api.soundFontLoaded.on(function(){
      st.textContent='soundfont loaded';
      FlutterChannel.postMessage(JSON.stringify({type:'sf_loaded'}));
    });
    window.api.soundFontLoadFailed.on(function(e){
      st.textContent='sf load failed';
      FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'soundfont: '+(e&&e.message||e)}));
    });
    window.api.playerReady.on(function(){
      st.textContent='player ready';
    });
    window.api.scoreLoaded.on(function(){
      st.textContent='score loaded';
      FlutterChannel.postMessage(JSON.stringify({type:'ready'}));
    });
    window.api.playerStateChanged.on(function(s){
      FlutterChannel.postMessage(JSON.stringify({type:'state',state:s.state}));
    });
    window.api.renderStarted.on(function(){
      st.textContent='rendering...';
    });
    window.api.renderFinished.on(function(){
      st.textContent='rendered';
    });

    window.loadScore=function(){
      try{
        st.textContent='loading score...';
        window.api.load('/score');
      }catch(e){
        st.textContent='load error';
        FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'load: '+e.message}));
      }
    };

    window.playScore=function(){
      try{
        if(!window.api)return;
        var ctx=window.__audioCtx;
        if(ctx&&ctx.state==='suspended')ctx.resume();
        window.api.play();
      }catch(e){
        FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'play: '+e.message}));
      }
    };

    window.pauseScore=function(){
      try{
        if(window.api)window.api.pause();
      }catch(e){
        FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'pause: '+e.message}));
      }
    };

    window.stopScore=function(){
      try{
        if(window.api)window.api.stop();
      }catch(e){
        FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'stop: '+e.message}));
      }
    };

    window.nextBar=function(){
      try{
        if(window.api)window.api.stop();
      }catch(e){
        FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'next: '+e.message}));
      }
    };

    window.prevBar=function(){
      try{
        if(window.api)window.api.stop();
      }catch(e){
        FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'prev: '+e.message}));
      }
    };

    FlutterChannel.postMessage(JSON.stringify({type:'js_ready'}));

    fetch('/sonivox.sf2').then(function(r){
      if(!r.ok)throw new Error('HTTP '+r.status);
      st.textContent='loading sf...';
      return r.arrayBuffer();
    }).then(function(buf){
      window.api.loadSoundFont(new Uint8Array(buf),false);
    }).catch(function(e){
      st.textContent='sf error';
      FlutterChannel.postMessage(JSON.stringify({type:'err',msg:'sf: '+e.message}));
    });
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
    if (_jsReady) await _loadScore();
  }

  Future<void> _loadScore() async {
    await _controller.runJavaScript('loadScore();');
  }

  Future<void> _play() async {
    await _controller.runJavaScript('playScore();');
  }

  Future<void> _pause() async {
    await _controller.runJavaScript('pauseScore();');
  }

  Future<void> _prev() async {
    await _controller.runJavaScript('prevBar();');
  }

  Future<void> _next() async {
    await _controller.runJavaScript('nextBar();');
  }

  void _onMsg(JavaScriptMessage msg) {
    try {
      final d = jsonDecode(msg.message) as Map<String, dynamic>;
      final type = d['type'] as String?;
      debugPrint('onMsg: $type ${msg.message}');
      switch (type) {
        case 'state':
          setState(() => _playerState = d['state'] as int);
        case 'sf_loaded':
          setState(() => _sfLoaded = true);
        case 'js_ready':
          setState(() => _jsReady = true);
          if (_ready) _loadScore();
        case 'err':
          debugPrint('alphaTab err: ${d['msg']}');
      }
    } catch (e) {
      debugPrint('onMsg parse error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _playerState == 1;
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
                  onPressed: _sfLoaded ? _prev : null,
                ),
                const SizedBox(width: 16),
                FloatingActionButton(
                  mini: true,
                  onPressed: (_sfLoaded && _ready)
                      ? (isPlaying ? _pause : _play)
                      : null,
                  backgroundColor: isPlaying ? Colors.red : Colors.brown,
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _sfLoaded ? _next : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
