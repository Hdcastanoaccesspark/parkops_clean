import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/parkops_components.dart';

class TecnicoReportesScreen extends StatefulWidget {
  const TecnicoReportesScreen({super.key});
  @override
  State<TecnicoReportesScreen> createState() => _TecnicoReportesScreenState();
}

class _TecnicoReportesScreenState extends State<TecnicoReportesScreen> {
  List<dynamic> _reportes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarReportes();
  }

  Future<void> _cargarReportes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      setState(() {
        _error = 'No autenticado';
        _loading = false;
      });
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('$API_BASE_URL/tecnico/mis_reportes_completados'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _reportes = data;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Error al cargar reportes (${response.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de conexión: $e';
        _loading = false;
      });
    }
  }

  Future<void> _descargarPdf(String pdfUrl) async {
    final url = '$API_BASE_URL$pdfUrl';
    final uri = Uri.parse(url);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        throw Exception('No autenticado');
      }
      _msg('Descargando PDF...', err: false);
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/reporte_${pdfUrl.split('/').last}.pdf');
        await file.writeAsBytes(response.bodyBytes);
        await OpenFile.open(file.path);
      } else {
        throw Exception('Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      _msg('No se pudo descargar el PDF: $e');
    }
  }

  void _msg(String m, {bool err = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: err ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('Mis Reportes Completados'),
        backgroundColor: AppTheme.darkSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarReportes,
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
                    onPressed: _cargarReportes,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          : _reportes.isEmpty
          ? const Center(
              child: Text(
                'No hay reportes finalizados',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _reportes.length,
              itemBuilder: (context, index) {
                final r = _reportes[index];
                return ParkopsCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(
                      '#${r['id']} - ${r['tipo']}',
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r['descripcion'] ?? 'Sin descripción',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Parqueadero: ${r['parqueadero_nombre'] ?? 'No especificado'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.info,
                          ),
                        ),
                        if (r['fecha_fin'] != null)
                          Text(
                            'Fecha: ${r['fecha_fin'].substring(0, 10)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.picture_as_pdf,
                        color: AppTheme.success,
                      ),
                      onPressed: () => _descargarPdf(r['pdf_url']),
                    ),
                    onTap: () => _descargarPdf(r['pdf_url']),
                  ),
                );
              },
            ),
    );
  }
}
