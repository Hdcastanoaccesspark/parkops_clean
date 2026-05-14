import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ← AÑADIDO
import '../theme/app_theme.dart';
import '../widgets/parkops_components.dart';

class LiderDashboard extends StatefulWidget {
  const LiderDashboard({super.key});
  @override
  State<LiderDashboard> createState() => _LiderDashboardState();
}

class _LiderDashboardState extends State<LiderDashboard> {
  // Datos simulados para gráficos (luego se reemplazarán por datos reales)
  final List<double> _ticketsPorDia = [5, 8, 3, 10, 6, 7, 4];
  final List<double> _slaPorDia = [92, 88, 95, 80, 97, 90, 93];
  final List<String> _diasSemana = [
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];

  // Datos simulados para heatmap
  final List<Map<String, dynamic>> _heatmapData = [
    {'parqueadero': 'Centro', 'incidencias': 18},
    {'parqueadero': 'Unicentro', 'incidencias': 9},
    {'parqueadero': 'El Dorado', 'incidencias': 14},
    {'parqueadero': 'Chapinero', 'incidencias': 11},
    {'parqueadero': 'Salitre', 'incidencias': 7},
  ];

  // Alertas simuladas
  final List<Map<String, dynamic>> _alertas = [
    {
      'tipo': 'falla_recurrente',
      'mensaje': 'Validador Tarjeta en Parqueadero Centro (3 fallas en 7 días)',
    },
    {
      'tipo': 'tecnico_cargado',
      'mensaje': 'Técnico Juan tiene 5 tickets asignados',
    },
    {'tipo': 'sla_vencido', 'mensaje': 'Ticket #12 lleva 72 horas sin cierre'},
  ];

  // Top fallas simuladas
  final List<Map<String, dynamic>> _topFallas = [
    {'falla': 'No lee tarjeta', 'conteo': 12},
    {'falla': 'Brazo roto', 'conteo': 9},
    {'falla': 'Imagen borrosa', 'conteo': 8},
    {'falla': 'Atasco dispensador', 'conteo': 6},
    {'falla': 'No enciende', 'conteo': 5},
  ];

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
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- KPIs ejecutivos --
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
                    'SLA mensual',
                    '94%',
                    Icons.check_circle_outline,
                    AppTheme.success,
                  ),
                  _buildKpiCard(
                    'T. resolución',
                    '4.2 h',
                    Icons.timer_outlined,
                    AppTheme.info,
                  ),
                  _buildKpiCard(
                    'Costos op.',
                    '\$2.1M',
                    Icons.attach_money,
                    AppTheme.warning,
                  ),
                  _buildKpiCard(
                    'Clientes críticos',
                    '2',
                    Icons.people_outline,
                    AppTheme.error,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // -- Gráficos --
            const Text(
              'Tendencia semanal',
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
                  maxY: 12,
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
                          if (index >= 0 && index < _diasSemana.length) {
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
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 16),
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
                          if (index >= 0 && index < _diasSemana.length) {
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
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // -- Heatmap --
            const Text(
              'Incidencias por parqueadero',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
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
                final ratio = (data['incidencias'] as int) / max;
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
            ),
            const SizedBox(height: 24),

            // -- Alertas --
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
                case 'tecnico_cargado':
                  icon = Icons.person_off;
                  color = AppTheme.error;
                  break;
                case 'sla_vencido':
                  icon = Icons.timer_off;
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
            const SizedBox(height: 24),

            // -- Top fallas --
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
                        style: const TextStyle(color: AppTheme.textPrimary),
                      ),
                    ),
                    Text(
                      '${falla['conteo']} casos',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              );
            }),
          ],
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
