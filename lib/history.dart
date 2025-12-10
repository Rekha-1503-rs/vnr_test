import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'Controller/punch_in_controller.dart';
import 'map_view.dart';

class HistoryScreen extends StatelessWidget {
  final PunchController controller = Get.find<PunchController>();

  HistoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    controller.loadLastNDaysGrouped(days: 5);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Punch History'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: ElevatedButton.icon(
              onPressed: () {
                Get.to(() => MapViewScreen());
              },
              icon: const Icon(Icons.map),
              label: const Text("View Map of Last 5 Days"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),

          Expanded(
            child: Obx(() {
              if (controller.groupedPunches.isEmpty) {
                return const Center(
                  child: Text("No data found", style: TextStyle(fontSize: 16)),
                );
              }

              final keys = controller.groupedPunches.keys.toList()
                ..sort((a, b) => b.compareTo(a));

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: keys.length,
                itemBuilder: (_, index) {
                  final dateKey = keys[index];
                  final punches = controller.groupedPunches[dateKey] ?? [];

                  return Card(
                    elevation: 3,
                    margin: const EdgeInsets.only(bottom: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // DATE HEADER
                          Text(
                            DateFormat(
                              'dd MMM yyyy',
                            ).format(DateTime.parse(dateKey)),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // NO RECORDS
                          punches.isEmpty
                              ? const Text(
                                  "No punches recorded",
                                  style: TextStyle(color: Colors.grey),
                                )
                              : Column(
                                  children: punches.map((p) {
                                    final punchTime = DateTime.parse(
                                      p.timestamp.toString(),
                                    );

                                    return ListTile(
                                      leading: const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                      ),
                                      title: Text(
                                        DateFormat('hh:mm a').format(punchTime),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        "${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}\n${p.address}",
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}
