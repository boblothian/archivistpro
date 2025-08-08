import 'package:castscreen/castscreen.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;

  List<Device> _devices = [];
  Device? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );
    await _videoController.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoController,
      autoPlay: true,
      looping: false,
    );
    setState(() {});
  }

  Future<void> _searchDevices() async {
    final devices = await CastScreen.discoverDevice(
      timeout: const Duration(seconds: 5),
    );
    setState(() {
      _devices = devices;
      _selectedDevice = devices.isNotEmpty ? devices.first : null;
    });
  }

  Future<void> _castToDevice(Device device) async {
    final alive = await device.alive();
    if (!alive) return;

    await device.setAVTransportURI(SetAVTransportURIInput(widget.videoUrl));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Casting to ${device.spec.friendlyName}')),
    );
  }

  Future<void> _stopCasting() async {
    if (_selectedDevice == null) return;
    final alive = await _selectedDevice!.alive();
    if (!alive) return;
    await _selectedDevice!.stop(const StopInput());
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Stopped casting')));
  }

  @override
  void dispose() {
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Search Devices',
            onPressed: _searchDevices,
          ),
          PopupMenuButton<Device>(
            icon: const Icon(Icons.cast),
            tooltip: _devices.isNotEmpty ? 'Select device' : 'No devices found',
            onSelected: (device) {
              _selectedDevice = device;
              _castToDevice(device);
            },
            enabled: _devices.isNotEmpty,
            itemBuilder:
                (context) =>
                    _devices
                        .map(
                          (d) => PopupMenuItem(
                            value: d,
                            child: Text(d.spec.friendlyName),
                          ),
                        )
                        .toList(),
          ),
          if (_selectedDevice != null)
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: 'Stop Casting',
              onPressed: _stopCasting,
            ),
        ],
      ),
      body:
          _chewieController != null &&
                  _chewieController!.videoPlayerController.value.isInitialized
              ? Chewie(controller: _chewieController!)
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
