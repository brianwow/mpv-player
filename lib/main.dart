import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MPV Player',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF722B72),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

List<dynamic> multipleJsonByteDecoder(Uint8List data) {
  return utf8
      .decode(data)
      .split('\n')
      .map((e) {
        try {
          return jsonDecode(e);
        } catch (_) {
          return null;
        }
      })
      .where((e) => e != null)
      .toList();
}

class _MyHomePageState extends State<MyHomePage> {
  double? playbackTime;
  Socket? socket;
  double? timePos;
  double? percentPos;
  double? volume;
  double? duration;
  String? mediaTitle;
  String? subText;
  String? path;
  String socketAddress = '/tmp/mpvsocket';
  bool timestampRemaining = false;
  bool? paused;
  bool? muted;

  @override
  void initState() {
    _connectSocket();

    super.initState();
  }

  void _connectSocket() {
    Socket.connect(
      InternetAddress(socketAddress, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 3),
    ).then((socket) {
      setState(() {
        this.socket = socket;
      });

      socket.map(multipleJsonByteDecoder).listen(
        (decodedData) {
          if (kDebugMode) {
            print(decodedData);
          }
          for (final e in decodedData) {
            switch (e) {
              case {
                  'event': 'property-change',
                  'name': 'volume',
                  'data': final double data,
                }:
                volume = data;
              case {
                  'event': 'property-change',
                  'name': 'duration',
                  'data': final double data,
                }:
                duration = data;
              case {
                  'event': 'property-change',
                  'name': 'time-pos',
                  'data': final double data,
                }:
                timePos = data;
              case {
                  'event': 'property-change',
                  'name': 'pause',
                  'data': final bool data,
                }:
                paused = data;
              case {
                  'event': 'property-change',
                  'name': 'mute',
                  'data': final bool data,
                }:
                muted = data;
              case {
                  'event': 'property-change',
                  'name': 'media-title',
                  'data': final String data,
                }:
                mediaTitle = data;
              case {
                  'event': 'property-change',
                  'name': 'sub-text',
                  'data': final String data,
                }:
                subText = data;
              case {
                  'event': 'property-change',
                  'name': 'percent-pos',
                  'data': final double data,
                }:
                percentPos = data;
              case {
                  'event': 'property-change',
                  'name': 'path',
                  'data': final String data,
                }:
                if (data.startsWith("https://www.youtube.com")) {
                  path = data.substring(32);
                }
                subText = null;
            }
          }
          if (decodedData.isNotEmpty) setState(() {});
        },
        onDone: () => setState(() => this.socket = null),
      );

      socket
        ..writeln(jsonEncode({
          "command": ["observe_property", 1, "time-pos"]
        }))
        ..writeln(jsonEncode({
          "command": ["observe_property", 1, "pause"]
        }))
        ..writeln(jsonEncode({
          "command": ["observe_property", 1, "duration"]
        }))
        ..writeln(jsonEncode({
          "command": ["observe_property", 1, "volume"]
        }))
        ..writeln(jsonEncode({
          "command": ["observe_property", 1, "mute"]
        }))
        ..writeln(jsonEncode({
          "command": ["observe_property", 1, "percent-pos"]
        }))
        ..writeln(jsonEncode({
          "command": ["observe_property", 1, "sub-text"]
        }))
        ..writeln(jsonEncode({
          "command": ["observe_property", 1, "media-title"]
        }))
        ..writeln(jsonEncode({
          "command": ["observe_property", 1, "path"]
        }))
        ..flush();
    }).catchError((final e) {
      if (e case SocketException()) {
        final snackBar = SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('MPV socket unreachable: ${e.message.toString()}'),
        );

        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(snackBar);
      }
    });
  }

  String get timestamp {
    late final String? timePos;
    if (timestampRemaining) {
      timePos = this.timePos == null
          ? null
          : Duration(
              seconds: this.timePos!.toInt() - (this.duration?.toInt() ?? 0),
            ).toString().substring(0, 8);
    } else {
      timePos = this.timePos == null
          ? null
          : Duration(seconds: this.timePos!.toInt()).toString().substring(0, 7);
    }

    final String? duration = this.duration == null
        ? null
        : Duration(seconds: this.duration!.toInt()).toString().substring(0, 7);

    return timePos == null || duration == null
        ? '-:--:-- / -:--:--'
        : '$timePos / $duration';
  }

  void switchTimestampMode() =>
      setState(() => timestampRemaining = !timestampRemaining);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: socket == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextField(
                    onChanged: (final value) {
                      socketAddress = value;
                    },
                  ),
                  const SizedBox(height: 16),
                  MaterialButton(
                    onPressed: _connectSocket,
                    child: const Text('Connect socket'),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (path != null)
                          Container(
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                colorFilter: const ColorFilter.mode(
                                    Colors.black54, BlendMode.darken),
                                image: NetworkImage(
                                    'https://i.ytimg.com/vi/$path/hq720.jpg'),
                              ),
                            ),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                              child: Container(
                                decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.0)),
                              ),
                            ),
                          ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Slider(
                                    value: percentPos ?? 0,
                                    max: 100.0,
                                    onChanged: percentPos == null
                                        ? null
                                        : (final value) => socket?.writeln(
                                            '{"command":["set_property","percent-pos",$value]}'),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                GestureDetector(
                                  onTap: switchTimestampMode,
                                  child: Text(timestamp),
                                ),
                                const SizedBox(width: 16),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                '$mediaTitle',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                if (path != null)
                                  Positioned(
                                    left: 0,
                                    child: TextButton(
                                      onPressed: () {
                                        socket?.writeln(
                                            '{"command":["set_property", "pause", true]}');
                                        // https://youtu.be/aXaHB4gGAys?t=3
                                        launchUrl(Uri.https(
                                            'youtu.be',
                                            '/$path',
                                            (timePos != null)
                                                ? {'t': '${timePos?.toInt()}'}
                                                : {}));
                                      },
                                      child: const Text("Open in YouTube  "),
                                    ),
                                  ),
                                PlayerButton(socket: socket, paused: paused),
                                Positioned(
                                  right: 0,
                                  child: VolumeSlider(
                                      volume: volume,
                                      socket: socket,
                                      muted: muted),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 100),
                            child: Text(
                              subText ?? "",
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 38),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class VolumeSlider extends StatelessWidget {
  const VolumeSlider({
    super.key,
    required this.volume,
    required this.muted,
    required this.socket,
  });

  final double? volume;
  final bool? muted;
  final Socket? socket;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => socket?.writeln('{"command":["cycle","mute"]}'),
          icon: Icon(
              switch ((muted, volume)) {
                (true, _) => Icons.volume_off,
                final e when e.$2! > 50 => Icons.volume_up,
                final e when e.$2! > 25 => Icons.volume_down,
                _ => Icons.volume_mute,
              },
              size: 20),
        ),
        SizedBox(
          width: 150,
          child: Slider(
            label: volume?.toInt().toString(),
            divisions: 100,
            value: volume ?? 0,
            max: 150,
            onChanged: volume == null
                ? null
                : (final value) => socket
                    ?.writeln('{"command":["set_property","volume",$value]}'),
          ),
        ),
      ],
    );
  }
}

class PlayerButton extends StatelessWidget {
  const PlayerButton({
    super.key,
    required this.socket,
    required this.paused,
  });

  final Socket? socket;
  final bool? paused;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => socket?.writeln('{"command":["playlist-prev"]}'),
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton(
          onPressed: () => socket?.writeln('{"command":["cycle","pause"]}'),
          icon: Icon(
            (paused ?? false) ? Icons.play_arrow : Icons.pause_sharp,
            size: 36,
          ),
        ),
        IconButton(
          onPressed: () => socket?.writeln('{"command":["playlist-next"]}'),
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }
}
