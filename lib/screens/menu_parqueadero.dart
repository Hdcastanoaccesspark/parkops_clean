import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/parkops_components.dart';
import 'correctivo_presencial_screen.dart';
import 'correctivo_remoto_screen.dart';
import 'preventivo_screen.dart';
import 'qr_scanner_screen.dart';

class MenuParqueaderoScreen extends StatefulWidget {
  final Map<String, dynamic> parqueadero;
  const MenuParqueaderoScreen({super.key, required this.parqueadero});
  @override
  State<MenuParqueaderoScreen> createState() => _MenuParqueaderoScreenState();
}

class _MenuParqueaderoScreenState extends State<MenuParqueaderoScreen> {
  List<dynamic> _maquinas = [];
  bool _cargando = true;
  int? _solicitudActivaId;
  List<dynamic> _misReportes = [];
  List<dynamic> _reportesParqueadero = [];
  bool _cargandoReportes = false;

  @override
  void initState() {
    super.initState();
    _cargarMaquinas();
    _recuperarReporteActivo();
    _cargarMisReportes();
    _cargarReportesParqueadero();
  }

  Future<void> _cargarMaquinas() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final res = await http.get(
        Uri.parse(
          '$API_BASE_URL/parqueaderos/${widget.parqueadero['id']}/maquinas',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        setState(() {
          _maquinas = jsonDecode(res.body);
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      print('Error cargando máquinas: $e');
      setState(() => _cargando = false);
    }
  }

  Future<void> _recuperarReporteActivo() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('solicitudActivaId_${widget.parqueadero['id']}');
    if (id != null) {
      setState(() {
        _solicitudActivaId = id;
      });
    }
  }

  Future<void> _guardarReporteActivo() async {
    final prefs = await SharedPreferences.getInstance();
    if (_solicitudActivaId != null) {
      await prefs.setInt(
        'solicitudActivaId_${widget.parqueadero['id']}',
        _solicitudActivaId!,
      );
    } else {
      await prefs.remove('solicitudActivaId_${widget.parqueadero['id']}');
    }
  }

  Future<void> _cargarMisReportes() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final res = await http.get(
        Uri.parse(
          '$API_BASE_URL/tecnico/mis_reportes?parqueadero_id=${widget.parqueadero['id']}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        setState(() {
          _misReportes = jsonDecode(res.body);
        });
      }
    } catch (e) {
      print('Error cargando mis reportes: $e');
    }
  }

  Future<void> _cargarReportesParqueadero() async {
    setState(() => _cargandoReportes = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final res = await http.get(
        Uri.parse(
          '$API_BASE_URL/parqueaderos/${widget.parqueadero['id']}/reportes',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        setState(() {
          _reportesParqueadero = jsonDecode(res.body);
        });
      }
    } catch (e) {
      print('Error cargando reportes del parqueadero: $e');
    }
    setState(() => _cargandoReportes = false);
  }

  void _msg(String m, {bool err = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: err ? Colors.red : Colors.green,
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (_solicitudActivaId == null) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir del parqueadero'),
        content: const Text(
          'Tiene un reporte en curso. Si sale, perderá los cambios no guardados. ¿Desea salir?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _descargarPdf(int solicitudId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final url = '$API_BASE_URL/reporte/$solicitudId/pdf';

    try {
      _msg('Descargando PDF...', err: false);
      final res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/reporte_$solicitudId.pdf');
        await file.writeAsBytes(res.bodyBytes);
        await OpenFile.open(file.path);
      } else {
        _msg('Error al descargar el PDF (${res.statusCode})');
      }
    } catch (e) {
      _msg('No se pudo descargar el PDF: $e');
    }
  }

  Future<void> _correctivo() async {
    final tipo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tipo'),
        content: const Text('¿Remoto o presencial?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'remoto'),
            child: const Text('Remoto'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'presencial'),
            child: const Text('Presencial'),
          ),
        ],
      ),
    );
    if (tipo == null) return;

    if (tipo == 'remoto') {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CorrectivoRemotoScreen(parqueadero: widget.parqueadero),
        ),
      );
      if (result is int) {
        setState(() => _solicitudActivaId = result);
        await _guardarReporteActivo();
        _cargarMisReportes();
        _cargarReportesParqueadero();
      }
      return;
    }

    if (_maquinas.isEmpty) {
      _msg('No hay máquinas disponibles');
      return;
    }

    final maq = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selecciona máquina'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _maquinas.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(_maquinas[i]['nombre']),
              onTap: () => Navigator.pop(ctx, _maquinas[i]),
            ),
          ),
        ),
      ),
    );
    if (maq == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CorrectivoPresencialScreen(
          parqueadero: widget.parqueadero,
          maquina: maq,
        ),
      ),
    );
    if (result is int) {
      setState(() => _solicitudActivaId = result);
      await _guardarReporteActivo();
      _cargarMisReportes();
      _cargarReportesParqueadero();
    }
  }

  Future<void> _preventivo() async {
    if (_maquinas.isEmpty) {
      _msg('No hay máquinas disponibles');
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreventivoScreen(
          parqueadero: widget.parqueadero,
          maquinas: List<Map<String, dynamic>>.from(_maquinas),
        ),
      ),
    );
    if (result is int) {
      setState(() => _solicitudActivaId = result);
      await _guardarReporteActivo();
      _cargarMisReportes();
      _cargarReportesParqueadero();
    }
  }

  Future<void> _leerQR() async {
    final code = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (code != null) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final res = await http.get(
        Uri.parse('$API_BASE_URL/maquinas/qr/$code'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final maq = jsonDecode(res.body);
        if (maq['parqueadero_id'] != widget.parqueadero['id']) {
          _msg('Máquina de otro parqueadero');
          return;
        }
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CorrectivoPresencialScreen(
              parqueadero: widget.parqueadero,
              maquina: maq,
            ),
          ),
        );
        if (result is int) {
          setState(() => _solicitudActivaId = result);
          await _guardarReporteActivo();
          _cargarMisReportes();
          _cargarReportesParqueadero();
        }
      } else {
        _msg('No encontrada');
      }
    }
  }

  Future<void> _finalizar() async {
    if (_solicitudActivaId == null) {
      _msg('No hay un reporte activo para finalizar');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar labor'),
        content: const Text(
          '¿Está seguro de que desea finalizar la labor? Se requerirá la firma del cliente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final firmaBase64 = await _mostrarDialogoFirma();
    if (firmaBase64 == null) return;

    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar envío'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('¿Desea cerrar la solicitud con esta firma?'),
            const SizedBox(height: 10),
            Image.memory(base64Decode(firmaBase64), height: 100),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cambiar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (enviar == false) {
      _finalizar();
      return;
    }
    if (enviar != true) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final res = await http.post(
      Uri.parse('$API_BASE_URL/tecnico/cerrar_solicitud/$_solicitudActivaId'),
      headers: {'Authorization': 'Bearer $token'},
      body: {'items': 'Reporte completado', 'firma': firmaBase64},
    );
    if (res.statusCode == 200) {
      _msg('Labor finalizada. Reporte PDF generado.', err: false);
      setState(() {
        _solicitudActivaId = null;
      });
      await _guardarReporteActivo();
      _cargarMisReportes();
      _cargarReportesParqueadero();
    } else {
      _msg('Error al cerrar solicitud: ${res.statusCode}');
    }
  }

  Future<String?> _mostrarDialogoFirma() async {
    final SignatureController ctrl = SignatureController(
      penStrokeWidth: 2,
      penColor: Colors.black,
    );
    final result = await showGeneralDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      pageBuilder: (ctx, anim, secAnim) => Scaffold(
        backgroundColor: Colors.black54,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Container(
                  color: Colors.white,
                  margin: const EdgeInsets.all(16),
                  child: Signature(controller: ctrl),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => ctrl.clear(),
                      icon: const Icon(Icons.undo),
                      label: const Text('Borrar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (ctrl.isEmpty) {
                          _msg('Debe capturar la firma');
                          return;
                        }
                        final signatureBytes = await ctrl.toPngBytes();
                        Navigator.pop(ctx, signatureBytes);
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Confirmar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null) return null;
    return base64Encode(result);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: AppTheme.darkBackground,
        appBar: AppBar(
          title: Column(
            children: [
              Row(
                children: [
                  Image.network('https://i.imgur.com/dpfS4Xw.png', height: 40),
                  const SizedBox(width: 8),
                  const Text('Menú del Parqueadero'),
                ],
              ),
              Text(
                widget.parqueadero['nombre'],
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _boton(
                      'Mantenimiento Correctivo',
                      Icons.build,
                      _correctivo,
                    ),
                    const SizedBox(height: 12),
                    _boton(
                      'Mantenimiento Preventivo',
                      Icons.checklist,
                      _preventivo,
                    ),
                    const SizedBox(height: 12),
                    _boton(
                      'Leer QR de máquina',
                      Icons.qr_code_scanner,
                      _leerQR,
                    ),
                    const SizedBox(height: 12),
                    _boton(
                      'Finalizar labor (firma obligatoria)',
                      Icons.draw,
                      _finalizar,
                      isAccent: true,
                    ),
                    if (_solicitudActivaId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Reporte activo #$_solicitudActivaId',
                          style: const TextStyle(
                            color: AppTheme.warning,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const Divider(height: 30),
                    const Text(
                      'Reportes del Parqueadero',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    _cargandoReportes
                        ? const CircularProgressIndicator()
                        : _misReportes.isEmpty && _reportesParqueadero.isEmpty
                        ? const Text(
                            'No hay reportes disponibles',
                            style: TextStyle(color: AppTheme.textSecondary),
                          )
                        : Expanded(
                            child: ListView.builder(
                              itemCount:
                                  _misReportes.length +
                                  _reportesParqueadero.length,
                              itemBuilder: (_, i) {
                                if (i < _misReportes.length) {
                                  final reporte = _misReportes[i];
                                  final bool esFinalizada =
                                      reporte['estado'] == 'finalizada';
                                  return ListTile(
                                    title: Text(
                                      'Propio: ${reporte['tipo']}',
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      reporte['descripcion'] ?? '',
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ParkopsStatusBadge(
                                          status: reporte['estado'],
                                        ),
                                        const SizedBox(width: 8),
                                        if (!esFinalizada)
                                          ElevatedButton(
                                            onPressed: () {
                                              setState(
                                                () => _solicitudActivaId =
                                                    reporte['id'],
                                              );
                                              _guardarReporteActivo();
                                              _finalizar(); // lleva directamente a la firma
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  AppTheme.primaryBlue,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 6,
                                                  ),
                                              textStyle: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            child: const Text('Continuar'),
                                          ),
                                        if (esFinalizada)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.download,
                                              color: AppTheme.info,
                                            ),
                                            onPressed: () =>
                                                _descargarPdf(reporte['id']),
                                          ),
                                      ],
                                    ),
                                  );
                                } else {
                                  final reporte =
                                      _reportesParqueadero[i -
                                          _misReportes.length];
                                  return ListTile(
                                    title: Text(
                                      '${reporte['tipo']}',
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      reporte['descripcion'] ?? '',
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.download,
                                        color: AppTheme.info,
                                      ),
                                      onPressed: () =>
                                          _descargarPdf(reporte['id']),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _boton(
    String texto,
    IconData icon,
    VoidCallback onTap, {
    bool isAccent = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(texto),
        style: ElevatedButton.styleFrom(
          backgroundColor: isAccent ? AppTheme.accentRed : AppTheme.primaryBlue,
          foregroundColor: AppTheme.textPrimary,
          minimumSize: const Size(0, 45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
