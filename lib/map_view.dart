import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import 'Controller/punch_in_controller.dart';

class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key});

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  final PunchController controller = Get.find<PunchController>();
  final MapController mapController = MapController();

  LatLng? currentLatLng;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    _updatePosition(position);

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      _updatePosition(pos);
    });
  }

  void _updatePosition(Position pos) {
    setState(() {
      currentLatLng = LatLng(pos.latitude, pos.longitude);
    });

    if (mapController.camera != null) {
      mapController.move(currentLatLng!, 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    final punches = controller.recentPunches.reversed.toList();

    LatLng center = currentLatLng ??
        (punches.isNotEmpty
            ? LatLng(punches.first.latitude, punches.first.longitude)
            : LatLng(controller.designatedLat, controller.designatedLng));

    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        title: const Text(
          "Map View",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
      ),
      body: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 16,
        ),
        children: [
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          ),
          MarkerLayer(
            markers: [
              if (currentLatLng != null)
                Marker(
                  point: currentLatLng!,
                  width: 50,
                  height: 50,
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.blue,
                    size: 40,
                  ),
                ),
            ],
          )
        ],
      ),
    );
  }
}
