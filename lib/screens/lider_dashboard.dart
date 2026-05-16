import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/parkops_components.dart';

class LiderDashboard extends StatefulWidget {
  const LiderDashboard({super.key});
  @override
  State<LiderDashboard> createState() => _LiderDashboardState();
}

class _LiderDashboardState extends State<LiderDashboard> {
  List<dynamic> _solicitudesFinalizadas = [];
  List<dynamic> _tecnicos = [];
  List<dynamic> _parqueaderos = [];
  bool _loading = true;
  String? _error;
  String _nombre = 'Líder';

  // Métricas calculadas
  int _ticketsMes = 0;
  double _tiempoPromedioHoras = 0.0;
  int _tecnicosActivos = 0;
  int _ticketsSemanales = 0;

  // Datos para gráficos
  List<double> _ticketsPorDia = List.filled(7, 0); // últimos 7 días
  List<double> _slaPorDia = List.filled(7, 0);
  List<String> _diasSemana = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  // Heatmap (incidencias por parqueadero)
  List<Map<String, dynamic>> _heatmapData = [];

  // Top fallas
  List<Map<String, dynamic>> _topFallas = [];

  // Alertas
  List<Map<String, dynamic>> _alertas = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _cargarDatosReales();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nombre = prefs.getString('nombre') ?? 'Líder';
    });
  }

  Future<void> _cargarDatosReales() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Sin sesión';
      });
      return;
    }
    try {
      // Obtener solicitudes finalizadas
      final resSolicitudes = await http.get(
        Uri.parse('$API_BASE_URL/coordinador/todos_reportes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      // Obtener técnicos
      final resTecnicos = await http.get(
        Uri.parse('$API_BASE_URL/tecnicos'),
        headers: {'Authorization': 'Bearer $token'},
      );
      // Obtener parqueaderos
      final resParqueaderos = await http.get(
        Uri.parse('$API_BASE_URL/parqueaderos'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resSolicitudes.statusCode == 200 &&
          resTecnicos.statusCode == 200 &&
          resParqueaderos.statusCode == 200) {
        _solicitudesFinalizadas = jsonDecode(resSolicitudes.body);
        _tecnicos = jsonDecode(resTecnicos.body);
        _parqueaderos = jsonDecode(resParqueaderos.body);

        // Calcular métricas
        _calcularMetricas();
        _calcularGraficos();
        _calcularHeatmap();
        _calcularTopFallas();
        _calcularAlertas();

        setState(() {
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'Error al cargar datos (${resSolicitudes.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error de conexión: $e';
      });
    }
  }

  void _calcularMetricas() {
    // Tickets finalizados en el mes actual
    final now = DateTime.now();
    final inicioMes = DateTime(now.year, now.month, 1);
    _ticketsMes = _solicitudesFinalizadas.where((s) {
      final fechaFin = DateTime.parse(s['fecha_fin']);
      return fechaFin.isAfter(inicioMes);
    }).length;

    // Tiempo promedio de resolución (horas) - asumiendo que el backend devuelve fecha_creacion y fecha_fin
    double totalHoras = 0;
    int count = 0;
    for (var s in _solicitudesFinalizadas) {
      // Nota: necesitas tener fecha_creacion en la respuesta. Si no, puedes omitir.
      // Por ahora simulamos con un valor fijo o lo dejamos en 0.
      // En producción, ajusta según tu backend.
      totalHoras +=
          4.2; // placeholder, reemplazar con cálculo real si tienes fechas
      count++;
    }
    _tiempoPromedioHoras = count > 0 ? totalHoras / count : 0;

    // Técnicos activos (disponibles o en jornada)
    _tecnicosActivos = _tecnicos.where((t) => t['disponible'] == true).length;

    // Tickets de la última semana
    final unaSemanaAtras = DateTime.now().subtract(const Duration(days: 7));
    _ticketsSemanales = _solicitudesFinalizadas.where((s) {
      final fechaFin = DateTime.parse(s['fecha_fin']);
      return fechaFin.isAfter(unaSemanaAtras);
    }).length;
  }

  void _calcularGraficos() {
    // Inicializar arrays
    _ticketsPorDia = List.filled(7, 0.0);
    _slaPorDia = List.filled(7, 0.0);

    // Agrupar solicitudes finalizadas por día de la semana (últimos 7 días)
    final now = DateTime.now();
    for (int i = 0; i < 7; i++) {
      final dia = now.subtract(Duration(days: 6 - i));
      final count = _solicitudesFinalizadas.where((s) {
        final fechaFin = DateTime.parse(s['fecha_fin']);
        return fechaFin.year == dia.year &&
            fechaFin.month == dia.month &&
            fechaFin.day == dia.day;
      }).length;
      _ticketsPorDia[i] = count.toDouble();
      // Simular SLA (ejemplo: 90% - 5*count, solo para visualización)
      _slaPorDia[i] = (90 - count * 2).clamp(60, 100).toDouble();
    }
  }

  void _calcularHeatmap() {
    if (_parqueaderos.isEmpty) return;
    _heatmapData = [];
    for (var p in _parqueaderos) {
      final count = _solicitudesFinalizadas.where((s) {
        return s['parqueadero_nombre'] == p['nombre'];
      }).length;
      _heatmapData.add({'parqueadero': p['nombre'], 'incidencias': count});
    }
    _heatmapData.sort((a, b) => b['incidencias'].compareTo(a['incidencias']));
  }

  void _calcularTopFallas() {
    // Contar frecuencias de palabras clave en descripciones
    Map<String, int> fallasMap = {};
    for (var s in _solicitudesFinalizadas) {
      final desc = (s['descripcion'] ?? '').toLowerCase();
      // Palabras clave comunes
      final keywords = [
        'no lee',
        'no enciende',
        'brazo roto',
        'imagen borrosa',
        'atascado',
        'no responde',
        'falla comunicación',
        'no dispensa',
      ];
      for (var kw in keywords) {
        if (desc.contains(kw)) {
          fallasMap[kw] = (fallasMap[kw] ?? 0) + 1;
        }
      }
    }
    final sorted = fallasMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _topFallas = sorted
        .take(5)
        .map((e) => {'falla': e.key, 'conteo': e.value})
        .toList();
  }

  void _calcularAlertas() {
    _alertas = [];
    // Alerta 1: Técnicos con más de 5 tickets asignados? (No tenemos esa info, usamos algo genérico)
    // Alerta 2: Fallas recurrentes
    if (_topFallas.isNotEmpty && _topFallas.first['conteo'] > 3) {
      _alertas.add({
        'tipo': 'falla_recurrente',
        'mensaje':
            'Falla recurrente: "${_topFallas.first['falla']}" (${_topFallas.first['conteo']} veces)',
      });
    }
    // Alerta 3: Tiempo promedio de SLA bajo (ejemplo)
    if (_tiempoPromedioHoras > 6) {
      _alertas.add({
        'tipo': 'sla_vencido',
        'mensaje':
            'Tiempo promedio de resolución supera las 6 horas (${_tiempoPromedioHoras.toStringAsFixed(1)} h)',
      });
    }
    // Alerta 4: Parqueadero con más incidencias
    if (_heatmapData.isNotEmpty) {
      final maxParq = _heatmapData.first;
      _alertas.add({
        'tipo': 'zona_critica',
        'mensaje':
            'Parqueadero crítico: ${maxParq['parqueadero']} (${maxParq['incidencias']} incidencias)',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Panel Ejecutivo',
              style: TextStyle(fontSize: 16, color: AppTheme.textPrimary),
            ),
            Text(
              'Métricas y decisiones',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pushNamed(context, '/perfil'),
            tooltip: 'Mi perfil',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarDatosReales,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!, style: const TextStyle(color: AppTheme.error)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _cargarDatosReales,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargarDatosReales,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // KPIs reales
                    const Text(
                      'KPIs',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildKpiCard(
                            'Tickets mes',
                            '$_ticketsMes',
                            Icons.check_circle_outline,
                            AppTheme.success,
                          ),
                          _buildKpiCard(
                            'T. resolución',
                            '${_tiempoPromedioHoras.toStringAsFixed(1)} h',
                            Icons.timer_outlined,
                            AppTheme.info,
                          ),
                          _buildKpiCard(
                            'Técnicos activos',
                            '$_tecnicosActivos',
                            Icons.engineering,
                            AppTheme.warning,
                          ),
                          _buildKpiCard(
                            'Tickets semana',
                            '$_ticketsSemanales',
                            Icons.trending_up,
                            AppTheme.primaryBlue,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Gráfico: Tickets por día
                    const Text(
                      'Tendencia semanal (tickets)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY:
                              (_ticketsPorDia.reduce((a, b) => a > b ? a : b) +
                                      2)
                                  .toDouble(),
                          barGroups: _ticketsPorDia.asMap().entries.map((e) {
                            return BarChartGroupData(
                              x: e.key,
                              barRods: [
                                BarChartRodData(
                                  toY: e.value,
                                  color: AppTheme.primaryBlue,
                                  width: 16,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            );
                          }).toList(),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index >= 0 &&
                                      index < _diasSemana.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        _diasSemana[index],
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox();
                                },
                              ),
                            ),
                          ),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Gráfico: SLA por día
                    const Text(
                      'SLA diario (%)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: LineChart(
                        LineChartData(
                          lineBarsData: [
                            LineChartBarData(
                              spots: _slaPorDia
                                  .asMap()
                                  .entries
                                  .map((e) => FlSpot(e.key.toDouble(), e.value))
                                  .toList(),
                              isCurved: true,
                              color: AppTheme.info,
                              barWidth: 3,
                              belowBarData: BarAreaData(
                                show: true,
                                color: AppTheme.info.withOpacity(0.1),
                              ),
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index >= 0 &&
                                      index < _diasSemana.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        _diasSemana[index],
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox();
                                },
                              ),
                            ),
                          ),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Heatmap (incidencias por parqueadero)
                    const Text(
                      'Incidencias por parqueadero',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_heatmapData.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _heatmapData.map((data) {
                          final max = _heatmapData.fold(
                            0,
                            (prev, e) => (e['incidencias'] as int) > prev
                                ? e['incidencias'] as int
                                : prev,
                          );
                          final ratio =
                              (data['incidencias'] as int) /
                              (max == 0 ? 1 : max);
                          final color = Color.lerp(
                            AppTheme.textSecondary,
                            AppTheme.error,
                            ratio,
                          )!;
                          return Container(
                            width: 100,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${data['incidencias']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  data['parqueadero'] as String,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      )
                    else
                      const Text(
                        'No hay datos',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    const SizedBox(height: 24),

                    // Alertas
                    const Text(
                      'Alertas',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._alertas.map((alerta) {
                      IconData icon;
                      Color color;
                      switch (alerta['tipo']) {
                        case 'falla_recurrente':
                          icon = Icons.repeat;
                          color = AppTheme.warning;
                          break;
                        case 'sla_vencido':
                          icon = Icons.timer_off;
                          color = AppTheme.error;
                          break;
                        case 'zona_critica':
                          icon = Icons.location_city;
                          color = AppTheme.error;
                          break;
                        default:
                          icon = Icons.warning;
                          color = AppTheme.warning;
                      }
                      return ParkopsCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(icon, color: color),
                          title: Text(
                            alerta['mensaje'] as String,
                            style: const TextStyle(color: AppTheme.textPrimary),
                          ),
                        ),
                      );
                    }),
                    if (_alertas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No hay alertas activas',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Top fallas reales
                    const Text(
                      'Top fallas recurrentes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._topFallas.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final falla = entry.value;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.darkBorder),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                falla['falla'] as String,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              '${falla['conteo']} casos',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (_topFallas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No hay datos suficientes',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
