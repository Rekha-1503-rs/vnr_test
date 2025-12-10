import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../Models/punch_in_model.dart';
import '../db_helper/db_helper.dart';

class PunchController extends GetxController {
  // FIXED OFFICE LOCATION (CHANGE YOUR LAT/LNG)
  final double designatedLat = 28.6139;
  final double designatedLng = 77.2090;

  // Observables
  var currentPosition = Rxn<Position>();
  var currentDistance = 0.0.obs;
  var isWithinRadius = false.obs;
  var isPunching = false.obs;

  var recentPunches = <Punch>[].obs;
  var groupedPunches = <String, List<Punch>>{}.obs;

  DateTime? lastPunchTime;

  @override
  void onInit() {
    super.onInit();
    initLocation();
    loadRecentPunches();
    loadLastNDaysGrouped(days: 5);
  }

  // ------------------------------------------------------------
  // CONTINUOUS LOCATION TRACKING
  // ------------------------------------------------------------
  Future<void> initLocation() async {
    await Geolocator.requestPermission();

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      currentPosition.value = pos;

      final dist = Geolocator.distanceBetween(
        designatedLat,
        designatedLng,
        pos.latitude,
        pos.longitude,
      );

      currentDistance.value = dist;
      isWithinRadius.value = dist <= 1000; // 1 KM
    });
  }

  // ------------------------------------------------------------
  // CHECK IF USER CAN PUNCH
  // ------------------------------------------------------------
  bool get canPunch {
    if (!isWithinRadius.value) return false;

    if (lastPunchTime != null) {
      final now = DateTime.now();

      // Debounce 60 sec
      if (now.difference(lastPunchTime!) < const Duration(seconds: 60)) {
        return false;
      }

      // Prevent multiple in same day
      if (now.year == lastPunchTime!.year &&
          now.month == lastPunchTime!.month &&
          now.day == lastPunchTime!.day) {
        return false;
      }
    }

    return true;
  }

  // ------------------------------------------------------------
  // REVERSE GEOCODING
  // ------------------------------------------------------------
  Future<String> reverseGeocode(double lat, double lng) async {
    final placemarks = await placemarkFromCoordinates(lat, lng);
    if (placemarks.isEmpty) return "Unknown address";
    final p = placemarks.first;
    return "${p.street}, ${p.locality}, ${p.country}";
  }

  // ------------------------------------------------------------
  // LOAD LAST 20 PUNCHES (OR LAST 5 DAYS)
  // ------------------------------------------------------------
  Future<void> loadRecentPunches() async {
    recentPunches.value = await DBHelper.instance.getPunchesForLast5Days();
  }

  // ------------------------------------------------------------
  // PUNCH IN
  // ------------------------------------------------------------
  Future<void> punchIn() async {
    if (!canPunch) {
      Get.snackbar("Error", "Punch not allowed");
      return;
    }

    final pos = currentPosition.value;
    if (pos == null) {
      Get.snackbar("Error", "Location not ready");
      return;
    }

    isPunching.value = true;

    final address = await reverseGeocode(pos.latitude, pos.longitude);

    // IMPORTANT: timestamp stored as int (epoch)
    final punch = Punch(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      latitude: pos.latitude,
      longitude: pos.longitude,
      address: address,
    );

    await DBHelper.instance.insertPunch(punch);

    lastPunchTime = DateTime.now();

    await loadRecentPunches();
    await loadLastNDaysGrouped(days: 5);

    isPunching.value = false;

    Get.snackbar("Success", "Punch recorded successfully!");
  }

  // ------------------------------------------------------------
  // GROUP PUNCHES FOR LAST N DAYS
  // ------------------------------------------------------------
  Future<void> loadLastNDaysGrouped({int days = 5}) async {
    final now = DateTime.now();

    final startDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));

    final punches = await DBHelper.instance.getPunchesSince(startDate);

    final Map<String, List<Punch>> map = {};

    // Ensure all days exist
    for (int i = 0; i < days; i++) {
      final day = startDate.add(Duration(days: i));
      final key = _dateKey(day);
      map[key] = [];
    }

    // Group by date
    for (final p in punches) {
      final dt = DateTime.fromMillisecondsSinceEpoch(p.timestamp);
      final key = _dateKey(dt);

      if (!map.containsKey(key)) {
        map[key] = [];
      }
      map[key]!.add(p);
    }

    // Sort each day by time (newest first)
    map.forEach((key, list) {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });

    groupedPunches.value = map;
  }

  // ------------------------------------------------------------
  // FORMAT KEY
  // ------------------------------------------------------------
  String _dateKey(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);
}
