import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
// Using a small custom painter for the line chart instead of an external charting
// package to avoid version/constructor mismatches and simplify dependency management.

// Updated the API call to include the new baseline URL parameters
Future<Map<String, dynamic>> fetchWeatherJson(double lat, double lon) async {
  final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': lat.toString(),
    'longitude': lon.toString(),
    'daily': 'weather_code,temperature_2m_min,temperature_2m_max',
    'hourly': 'temperature_2m,precipitation,precipitation_probability,weather_code',
    // `current_weather=true` is the Open-Meteo way to request the current weather block
    'current_weather': 'true',
    'timezone': 'auto',
    'temperature_unit': 'fahrenheit',
  });
  final resp = await http.get(uri).timeout(const Duration(seconds: 10));
  if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

/// A minimal page that receives coordinates + optional city/zip from the caller.
class WeatherService extends StatefulWidget {
  final double lat;
  final double lon;
  final String zip;
  final String? cityName;

  const WeatherService({super.key, 
    required this.lat,
    required this.lon,
    required this.zip,
    this.cityName,
  });

  @override
  State<WeatherService> createState() => _WeatherServiceState();
}

class _WeatherServiceState extends State<WeatherService> {
  Map<String, dynamic>? _weatherJson;
  bool _loading = true;
  String? _error;
  //cpt
  int selectedDayIndex = 0;
  List<List<double>> tempsByDay = [];
  List<List<DateTime>> timesByDay = [];

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json = await fetchWeatherJson(widget.lat, widget.lon);
      setState(() {
        _weatherJson = json;
        _loading = false;
      });
      debugPrint('Weather JSON: ${json.toString()}');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      debugPrint('Weather fetch error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.cityName ?? widget.zip;
    return Scaffold(
      appBar: AppBar(title: Text('Weather for $title')),//title not showing anymore. Maybe needs to be grabbed on this page, rather than main.dart?
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
                ? Text('Error: $_error')
                : _weatherJson != null
                    ? SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('ZIP: ${widget.zip}'),

                            const SizedBox(height: 16),

                            Builder(builder: (context) {
                              double? currentTemp;
                              List<double> hourlyTemps = [];
                              try {
                                // Open-Meteo sometimes returns a `current_weather` block
                                // containing `temperature` and `weathercode`.
                                if (_weatherJson!.containsKey('current_weather')) {
                                  final cw = _weatherJson!['current_weather'];
                                  if (cw != null && cw['temperature'] != null) {
                                    currentTemp = (cw['temperature'] as num).toDouble();
                                  }
                                }
                                // Some requests (rarely) might return a `current` object; keep it as a fallback.
                                if (currentTemp == null && _weatherJson!.containsKey('current')) {
                                  final c = _weatherJson!['current'];
                                  if (c != null && c['temperature_2m'] != null) {
                                    currentTemp = (c['temperature_2m'] as num).toDouble();
                                  }
                                }
                                // Derive hourly temperatures by reading hourly.temperature_2m.
                                if (_weatherJson!.containsKey('hourly') && _weatherJson!['hourly'] != null) {
                                  final hourly = _weatherJson!['hourly'];
                                  final temps = hourly['temperature_2m'];
                                  if (temps != null && temps is List) {
                                    hourlyTemps = temps.map<double>((t) => (t as num).toDouble()).toList();
                                  }
                                }
                                // If still missing currentTemp, set it to the first hourly temp.
                                if (currentTemp == null && hourlyTemps.isNotEmpty) {
                                  currentTemp = hourlyTemps[0];
                                }
                              } catch (e) {
                                // Defensive — if anything fails, show 'No data' in the card.
                                debugPrint('Parsing weather json failed: $e');
                              }

                              if (currentTemp == null || hourlyTemps.isEmpty) {
                                return const Text('Weather data unavailable');
                              }
                              //cpt
                              final now = DateTime.now();
                              final hourlyTimes = (_weatherJson!['hourly']['time'] as List)
                                  .map((t) => DateTime.parse(t))
                                  .toList();

                              // Find nearest hour index
                              int currentIndex = 0;
                              for (int i = 0; i < hourlyTimes.length; i++) {
                                if (hourlyTimes[i].isAfter(now)) {
                                  currentIndex = (i == 0) ? 0 : i - 1;
                                  break;
                                }
                              }
// ---------- GROUP HOURLY DATA INTO CALENDAR DAYS (Option A) ----------
final Map<String, List<int>> indexByDate = {};
for (int i = 0; i < hourlyTimes.length; i++) {
  final local = hourlyTimes[i].toLocal();
  final key = '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  indexByDate.putIfAbsent(key, () => []);
  indexByDate[key]!.add(i);
}
//format hours into AM/PM
// String formatHour(DateTime time) {
//   final hour = time.hour;
//   final ampm = hour >= 12 ? 'PM' : 'AM';
//   final displayHour = hour % 12 == 0 ? 12 : hour % 12;
//   return '$displayHour $ampm';
// }

// Sort date keys and take the first 7 (today -> +6 days)
final sortedKeys = indexByDate.keys.toList()
  ..sort((a, b) => a.compareTo(b));
final usedKeys = sortedKeys.take(7).toList();

// Build timesByDay & tempsByDay aligned to indices
timesByDay = usedKeys
    .map((k) => indexByDate[k]!.map((idx) => hourlyTimes[idx]).toList())
    .toList();
tempsByDay = usedKeys
    .map((k) => indexByDate[k]!.map((idx) => hourlyTemps[idx]).toList())
    .toList();

// Ensure selectedDayIndex is valid
if (selectedDayIndex >= tempsByDay.length) {
  selectedDayIndex = 0;
}

// Helper to format weekday/day
String weekdayAbbrev(DateTime d) {
  const names = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  return names[d.weekday % 7];
}
String monthDayLabel(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

// Determine selected-day arrays (fallback to the full hourly list if something's wrong)
final selectedTemps = (tempsByDay.isNotEmpty && selectedDayIndex < tempsByDay.length)
    ? tempsByDay[selectedDayIndex]
    : hourlyTemps;
// final selectedTimes = (timesByDay.isNotEmpty && selectedDayIndex < timesByDay.length)
//     ? timesByDay[selectedDayIndex]
//     : hourlyTimes;

// Use the same currentIndex calculation but relative to the selectedTimes if needed.
// We already computed 'currentIndex' relative to the full hourlyTimes earlier,
// so if you want the highlighted marker to reflect the selected day, we must map it:
int selectedCurrentIndex = currentIndex;
if (timesByDay.isNotEmpty && selectedDayIndex < timesByDay.length) {
  // Map the original currentIndex to the index within the selected day (or -1 if not present)
  final mapping = indexByDate[usedKeys[selectedDayIndex]]!;
  final posInMapping = mapping.indexWhere((i) => i == currentIndex);
  selectedCurrentIndex = posInMapping >= 0 ? posInMapping : 0;
}

// ---------- UI: WeatherCard (summary), Day selector row, and Chart ----------
return Column(
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    // keep the existing WeatherCard to show current temp & summary (we removed chart from inside it)
    WeatherCard(
      currentTemperature: currentTemp,
      hourlyTemperatures: selectedTemps, // keep for compatibility if WeatherCard still expects it
      currentIndex: selectedCurrentIndex,
    ),

    const SizedBox(height: 48),

    // Day selector: horizontal scroll of up to 7 days

    // const SizedBox(height: 24),


    // Chart for the selected day
    SizedBox(
      height: 220,
      child: HourlyLineChart(
        values: selectedTemps,
        currentIndex: selectedCurrentIndex,
        hourlyTimes: hourlyTimes,
      ),
    ),
        SizedBox(
      height: 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: usedKeys.length,
        itemBuilder: (ctx, i) {
          final firstDate = timesByDay[i].first;
          final weekday = weekdayAbbrev(firstDate);
          final mmdd = monthDayLabel(firstDate);
          final isSelected = i == selectedDayIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  selectedDayIndex = i;
                });
              },
              child: Column(
                children: [
                  Text(
                    weekday,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      mmdd,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),

  ],
);

                          //cpt end
                            }),
                          ],
                        ),
                      )
                    : const Text('No data'),
      ),
    );
  }
}
//og
/*class WeatherCard extends StatelessWidget {
  final double currentTemperature;
  final List<double> hourlyTemperatures;

  const WeatherCard({super.key, required this.currentTemperature, required this.hourlyTemperatures});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Temperature: ${currentTemperature.toStringAsFixed(1)}°F',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16.0),
            Text(
              'Temperature Throughout the Day',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16.0),
            SizedBox(
              height: 200,
              child: HourlyLineChart(
                values: hourlyTemperatures,
                currentIndex: currentIndex,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
*/

//cpt 
class WeatherCard extends StatelessWidget {
  final double currentTemperature;
  final List<double> hourlyTemperatures;
  final int currentIndex;

  const WeatherCard({
    super.key,
    required this.currentTemperature,
    required this.hourlyTemperatures,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Temperature: ${currentTemperature.toStringAsFixed(1)}°F',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8.0),
            Text(
              'Tap a date below to view hourly temperatures for that day.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}


//cpt
class HourlyLineChart extends StatefulWidget {
  final List<double> values;
  final int currentIndex;
  final List<DateTime> hourlyTimes;

  const HourlyLineChart({
    super.key,
    required this.values,
    required this.currentIndex,
    required this.hourlyTimes,
  });

  @override
  State<HourlyLineChart> createState() => _HourlyLineChartState();
}

class _HourlyLineChartState extends State<HourlyLineChart> {
  int? _scrubIndex; // This is the value CustomPaint will read

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        // We'll calculate scrubIndex based on local position
        final box = context.findRenderObject() as RenderBox;
        final localX = box.globalToLocal(details.globalPosition).dx;
        final chartWidth = box.size.width - 32.0 - 8.0; // same padding as painter
        int idx = ((localX - 32.0) / chartWidth * (widget.values.length - 1)).round();
        if (idx < 0) idx = 0;
        if (idx >= widget.values.length) idx = widget.values.length - 1;
        setState(() {
          _scrubIndex = idx;
        });
      },
      onHorizontalDragEnd: (_) {
        // Optionally reset when drag ends
        setState(() {
          _scrubIndex = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: CustomPaint(
          painter: _LineChartPainter(
            widget.values,
            Theme.of(context).colorScheme.primary,
            widget.currentIndex,
            widget.hourlyTimes,
            scrubIndex: _scrubIndex, // now recognized
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// class _LineChartPainter extends CustomPainter {
//   final List<double> values;
//   final Color lineColor;

//   _LineChartPainter(this.values, this.lineColor);
//cpt version
/*class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final int currentIndex;
  final List<DateTime> hourlyTimes;

  _LineChartPainter(this.values, this.lineColor, this.currentIndex,this.hourlyTimes,);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    const double paddingTop = 8.0;
    const double paddingBottom = 16.0;
    const double paddingLeft = 32.0;
    final double chartHeight = size.height - paddingTop - paddingBottom;
    final double chartWidth = size.width - paddingLeft - 8.0;
    
    final int n = values.length;
    final double denom = (n > 1) ? (n - 1).toDouble() : 1.0;

    double minVal = values.reduce((a, b) => a < b ? a : b);
    double maxVal = values.reduce((a, b) => a > b ? a : b);
    double range = (maxVal - minVal).abs();
    if (range == 0) range = 1;

    // Use withAlpha to avoid the withOpacity deprecation warning:
    final Paint gridPaint = Paint()
      ..color = Colors.grey.withAlpha((0.2 * 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw min/max text on left
    final TextPainter minTp = TextPainter(
      text: TextSpan(text: minVal.toStringAsFixed(0), style: const TextStyle(color: Colors.black, fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    minTp.paint(canvas, Offset(4, paddingTop + chartHeight - minTp.height / 2));

    final TextPainter maxTp = TextPainter(
      text: TextSpan(text: maxVal.toStringAsFixed(0), style: const TextStyle(color: Colors.black, fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    maxTp.paint(canvas, Offset(4, paddingTop - maxTp.height / 2));

    // Draw grid lines: top and bottom
    canvas.drawLine(Offset(paddingLeft, paddingTop), Offset(paddingLeft + chartWidth, paddingTop), gridPaint);
    canvas.drawLine(Offset(paddingLeft, paddingTop + chartHeight), Offset(paddingLeft + chartWidth, paddingTop + chartHeight), gridPaint);
    //cpt
    // Draw hour labels along the x-axis
  // final TextStyle hourStyle = const TextStyle(color: Colors.black, fontSize: 10);
      for (int i = 0; i < n; i++) {
      // Only label every 3 hours
      if (i % 3 != 0) continue;

      final double x = paddingLeft + (chartWidth) * (i / denom);
      final String label = formatHour(hourlyTimes[i]); // hourlyTimes from WeatherService

      final TextPainter tp = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(color: Colors.black, fontSize: 10)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(x - tp.width / 2, paddingTop + chartHeight + 4));
    }

    // Build the path
    final path = Path();
    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final pointFillPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;


    for (int i = 0; i < n; i++) {
      final double x = paddingLeft + (chartWidth) * (i / denom);
      final double normalized = (values[i] - minVal) / range;
      final double y = paddingTop + (chartHeight - normalized * chartHeight);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw the line
    canvas.drawPath(path, pointPaint);

    // Draw points
    for (int i = 0; i < n; i++) {
      final double x = paddingLeft + (chartWidth) * (i / denom);
      final double normalized = (values[i] - minVal) / range;
      final double y = paddingTop + (chartHeight - normalized * chartHeight);
      canvas.drawCircle(Offset(x, y), 3.0, pointFillPaint);
    }

    // Draw special marker at currentIndex
    if (currentIndex >= 0 && currentIndex < values.length) {
      final double x = paddingLeft + (chartWidth) * (currentIndex / denom);
      final double norm = (values[currentIndex] - minVal) / range;
      final double y = paddingTop + (chartHeight - norm * chartHeight);

      final Paint highlightPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;

      // Draw a slightly larger point
      canvas.drawCircle(Offset(x, y), 5.0, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
           oldDelegate.lineColor != lineColor ||
           oldDelegate.currentIndex != currentIndex;
  }
}
*/
class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final int currentIndex; // original current time
  final int? scrubIndex; // user scrubbed index
  final List<DateTime> hourlyTimes;

  _LineChartPainter(
    this.values,
    this.lineColor,
    this.currentIndex,
    this.hourlyTimes, {
    this.scrubIndex,
  });

  

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    const double paddingTop = 24.0; // leave extra for scrub label
    const double paddingBottom = 16.0;
    const double paddingLeft = 32.0;
    final double chartHeight = size.height - paddingTop - paddingBottom;
    final double chartWidth = size.width - paddingLeft - 8.0;

    final int n = values.length;
    final double denom = (n > 1) ? (n - 1).toDouble() : 1.0;

    double minVal = values.reduce((a, b) => a < b ? a : b);
    double maxVal = values.reduce((a, b) => a > b ? a : b);
    double range = (maxVal - minVal).abs();
    if (range == 0) range = 1;

    final Paint gridPaint = Paint()
      ..color = Colors.grey.withAlpha((0.2 * 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw min/max text
    final TextPainter minTp = TextPainter(
      text: TextSpan(text: minVal.toStringAsFixed(0), style: const TextStyle(color: Colors.black, fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    minTp.paint(canvas, Offset(4, paddingTop + chartHeight - minTp.height / 2));

    final TextPainter maxTp = TextPainter(
      text: TextSpan(text: maxVal.toStringAsFixed(0), style: const TextStyle(color: Colors.black, fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    maxTp.paint(canvas, Offset(4, paddingTop - maxTp.height / 2));

    // Grid lines: top/bottom
    canvas.drawLine(Offset(paddingLeft, paddingTop), Offset(paddingLeft + chartWidth, paddingTop), gridPaint);
    canvas.drawLine(Offset(paddingLeft, paddingTop + chartHeight), Offset(paddingLeft + chartWidth, paddingTop + chartHeight), gridPaint);

    // Build line path
    final path = Path();
    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final pointFillPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final double x = paddingLeft + (chartWidth) * (i / denom);
      final double normalized = (values[i] - minVal) / range;
      final double y = paddingTop + (chartHeight - normalized * chartHeight);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, pointPaint);

    // Draw points
    for (int i = 0; i < n; i++) {
      final double x = paddingLeft + (chartWidth) * (i / denom);
      final double normalized = (values[i] - minVal) / range;
      final double y = paddingTop + (chartHeight - normalized * chartHeight);
      canvas.drawCircle(Offset(x, y), 3.0, pointFillPaint);
    }

    // Draw fixed current-time marker
    if (currentIndex >= 0 && currentIndex < values.length) {
      final double x = paddingLeft + (chartWidth) * (currentIndex / denom);
      final double y = paddingTop + chartHeight - ((values[currentIndex] - minVal) / range) * chartHeight;

      final Paint highlightPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), 5.0, highlightPaint);
    }

    // Draw scrub marker + floating label
    if (scrubIndex != null && scrubIndex! >= 0 && scrubIndex! < values.length) {
      final double x = paddingLeft + (chartWidth) * (scrubIndex! / denom);
      final double y = paddingTop + chartHeight - ((values[scrubIndex!] - minVal) / range) * chartHeight;

      // Scrub marker (blue, for example)
      final Paint scrubPaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 5.0, scrubPaint);

      // Floating label above chart
      final String label = '${values[scrubIndex!].toStringAsFixed(1)}°F @ ${formatHour(hourlyTimes[scrubIndex!])}';
      final TextPainter tp = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      final double labelX = (x - tp.width / 2).clamp(0, size.width - tp.width);
      tp.paint(canvas, Offset(labelX, 4)); // fixed y position
    }

    // Draw hour labels along x-axis (every 3 hours)
    final TextStyle hourStyle = const TextStyle(color: Colors.black, fontSize: 10);
    for (int i = 0; i < n; i++) {
      if (i % 3 != 0) continue;

      final double x = paddingLeft + (chartWidth) * (i / denom);
      final String label = formatHour(hourlyTimes[i]);
      final TextPainter tp = TextPainter(
        text: TextSpan(text: label, style: hourStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, paddingTop + chartHeight + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
           oldDelegate.lineColor != lineColor ||
           oldDelegate.currentIndex != currentIndex ||
           oldDelegate.scrubIndex != scrubIndex;
  }

  // Helper
  String formatHour(DateTime time) {
    final hour = time.hour;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour $ampm';
  }
}

//helper function for hourStyle
String formatHour(DateTime time) {
  final hour = time.hour;
  final ampm = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour $ampm';
}

/*TODO list:

1. Make the API call to OpenMeteo and store the json. 
    Time the API call so that it is made either upon entering the page, or upon the user having pressed the search button on the previous page.
2. Develop widgets for the weather at the moment of searching based on the designing I have made prior
  2a. Develop a refresh feature (Give a cooldown/only allow updating every 10 minutes)
  2b. Develop a cooldown/refresh timer to display 
3. Build Hamburger Menu
4?: Develop option for user to add more / remove pre-existing locations to check weather for.
5. Figure out how to find, pick, and choose, and design graphics for this.


  How to interpret the JSON data: 1. Understand the structure of the JSON data returned by OpenMeteo.
 2. Identify the key weather parameters needed for display, mostly temperature really.

*/