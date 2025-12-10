import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'Controller/punch_in_controller.dart';
import 'home_Screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final controller = Get.put(PunchController());
  await controller.initLocation();

  runApp(GetMaterialApp(debugShowCheckedModeBanner: false, home: HomeScreen()));
}
