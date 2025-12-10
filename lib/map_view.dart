import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'Controller/punch_in_controller.dart';

class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key});

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  final PunchController controller = Get.find<PunchController>();

  LatLng? currentLatLng; // store user current location

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  // ------------------------------------------------------------
  // GET THE CURRENT LOCATION (NO API KEY NEEDED)
  // ------------------------------------------------------------
  Future<void> _fetchCurrentLocation() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      currentLatLng = LatLng(position.latitude, position.longitude);
    });
  }

  @override
  Widget build(BuildContext context) {
    final punches = controller.recentPunches.toList().reversed.toList();
    final List<Marker> markers = [];
    final List<LatLng> points = [];

    for (var punch in punches) {
      final pos = LatLng(punch.latitude, punch.longitude);
      points.add(pos);

      final dateTime = DateTime.fromMillisecondsSinceEpoch(punch.timestamp);
      final formatted = DateFormat("dd MMM, hh:mm a").format(dateTime);

      markers.add(
        Marker(
          point: pos,
          width: 140,
          height: 70,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  formatted,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
              const Icon(Icons.location_pin, color: Colors.red, size: 36),
            ],
          ),
        ),
      );
    }

    // ------------------------------------------------------------
    // CALCULATE MAP CENTER
    // ------------------------------------------------------------
    LatLng center;

    if (currentLatLng != null) {
      center = currentLatLng!;
    } else if (points.isNotEmpty) {
      double lat = 0;
      double lng = 0;

      for (var p in points) {
        lat += p.latitude;
        lng += p.longitude;
      }

      center = LatLng(lat / points.length, lng / points.length);
    } else {
      center = LatLng(controller.designatedLat, controller.designatedLng);
    }

    // ------------------------------------------------------------
    // BUILD MAP
    // ------------------------------------------------------------
    return Scaffold(
      appBar: AppBar(
        title: const Text("Map View (With Current Location)"),
        backgroundColor: Colors.blueAccent,
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: 16,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          ),
          CurrentLocationLayer(),
          if (points.length > 1)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 4,
                  color: Colors.blueAccent,
                ),
              ],
            ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}
