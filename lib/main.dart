import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

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

class _MyHomePageState extends State<MyHomePage> {
  double? playbackTime;
  Socket? socket;
  double? timePos;
  double? percentPos;
  double? volume;
  double? duration;
  String? mediaTitle;
  String socketAddress = '/tmp/mpvsocket';
  bool timestampRemaining = false;
  bool? paused;

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

      socket.listen(
        (event) {
          final List<dynamic> decodedData = utf8
              .decode(event)
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
                  'name': 'media-title',
                  'data': final String data,
                }:
                mediaTitle = data;
              case {
                  'event': 'property-change',
                  'name': 'percent-pos',
                  'data': final double data,
                }:
                percentPos = data;
            }
          }

          if (decodedData.isNotEmpty) setState(() {});
        },
        onDone: () {
          setState(() => this.socket = null);
        },
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
          "command": ["observe_property", 1, "percent-pos"]
        }))
        ..writeln(jsonEncode({
          "command": ["observe_property", 1, "metatada"]
        }))
        ..writeln(jsonEncode({
          "command": ["observe_property", 1, "media-title"]
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
        padding: const EdgeInsets.all(16),
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
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      '$mediaTitle',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      PlayerButton(socket: socket, paused: paused),
                      Positioned(
                        right: 0,
                        child: VolumeSlider(volume: volume, socket: socket),
                      ),
                    ],
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
    required this.socket,
  });

  final double? volume;
  final Socket? socket;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.volume_up, size: 20),
        SizedBox(
          width: 150,
          child: Slider(
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
