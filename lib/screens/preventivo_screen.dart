import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class PreventivoScreen extends StatefulWidget {
  final Map<String, dynamic> parqueadero;
  final List<Map<String, dynamic>> maquinas;
  const PreventivoScreen({
    super.key,
    required this.parqueadero,
    required this.maquinas,
  });
  @override
  State<PreventivoScreen> createState() => _PreventivoScreenState();
}

class _PreventivoScreenState extends State<PreventivoScreen> {
  bool _backupRealizado = false;
  bool _preguntandoBackup = true;
  Map<String, dynamic> _maquinaSeleccionada = {};
  List<String> _fotosAntes = [], _fotosDespues = [], _fotosCotizacion = [];
  final _obs = TextEditingController();
  String _cotizacionRepuesto = '', _motivoNoBackup = '';
  bool _requiereCotizacion = false,
      _mostrandoChecklist = false,
      _enviando = false;
  final Map<String, String> _mediciones = {
    'faseNeutro': '',
    'faseTierra': '',
    'neutroTierra': '',
    'ups': '',
    'protectorVoltaje': '',
    'observacionesExtra': '',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preguntarBackup());
  }

  Future<void> _preguntarBackup() async {
    final c = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup de base de datos'),
        content: const Text('¿Se realizó el backup antes del mantenimiento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    if (c == true) {
      if (mounted) {
        setState(() {
          _backupRealizado = true;
          _preguntandoBackup = false;
        });
      }
      return;
    }
    final motivo = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Motivo'),
        content: TextField(
          decoration: const InputDecoration(
            hintText: '¿Por qué no se realizó el backup?',
          ),
          onChanged: (v) => _motivoNoBackup = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _motivoNoBackup),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (motivo != null && motivo.isNotEmpty) {
      if (mounted) {
        setState(() {
          _backupRealizado = true;
          _preguntandoBackup = false;
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debe especificar un motivo o realizar el backup'),
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  void _seleccionarMaquina(Map<String, dynamic> m) => setState(() {
    _maquinaSeleccionada = m;
    _mostrandoChecklist = true;
  });

  Future<void> _tomarFoto(String cat) async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera);
    if (f != null) {
      final b = await f.readAsBytes();
      if (cat == 'antes') {
        _fotosAntes.add(base64Encode(b));
      } else if (cat == 'despues')
        _fotosDespues.add(base64Encode(b));
      else
        _fotosCotizacion.add(base64Encode(b));
      setState(() {});
    }
  }

  void _mostrarDialogoFoto(List<String> fotos, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto'),
        content: const Text('¿Qué deseas hacer?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _mostrarFotoCompleta(fotos[index]);
            },
            child: const Text('Ver'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmarEliminarFoto(fotos, index);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _mostrarFotoCompleta(String base64) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(child: Image.memory(base64Decode(base64))),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarEliminarFoto(List<String> fotos, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text('¿Estás seguro de que deseas eliminar esta foto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => fotos.removeAt(index));
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildFotoLista(List<String> fotos) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(fotos.length, (index) {
        return GestureDetector(
          onTap: () => _mostrarDialogoFoto(fotos, index),
          child: Image.memory(
            base64Decode(fotos[index]),
            width: 80,
            height: 80,
            fit: BoxFit.cover,
          ),
        );
      }),
    );
  }

  Future<void> _cotDialog() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cotización'),
        content: const Text('¿Requiere repuestos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
        ],
      ),
    );
    if (r == true) {
      final rep = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text('Detalle'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(hintText: 'Ej: Batería'),
                  onChanged: (v) => _cotizacionRepuesto = v,
                ),
                const SizedBox(height: 8),
                _buildFotoLista(_fotosCotizacion),
                ElevatedButton.icon(
                  onPressed: () async {
                    await _tomarFoto('cotizacion');
                    setStateDialog(() {});
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Foto del repuesto'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, _cotizacionRepuesto),
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      );
      if (rep != null && rep.isNotEmpty) {
        setState(() {
          _requiereCotizacion = true;
          _cotizacionRepuesto = rep;
        });
      }
    }
  }

  Future<void> _guardar() async {
    if (_maquinaSeleccionada.isEmpty) {
      _msg('Selecciona una máquina');
      return;
    }
    if (!_backupRealizado) {
      _msg('Debes confirmar el backup');
      return;
    }
    if (_fotosAntes.isEmpty) {
      _msg('Debe tomar al menos una foto del ANTES');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar reporte'),
        content: const Text(
          '¿Confirma que desea guardar este reporte preventivo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _enviando = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    String d =
        'Preventivo en ${_maquinaSeleccionada['nombre']}\n'
        'Mediciones: F-N=${_mediciones['faseNeutro']}V, F-T=${_mediciones['faseTierra']}V, N-T=${_mediciones['neutroTierra']}V, UPS=${_mediciones['ups']}V, Protector=${_mediciones['protectorVoltaje']}V\n'
        'Obs extra: ${_mediciones['observacionesExtra']}\n'
        'Obs generales: ${_obs.text}\n'
        'Cotización: ${_requiereCotizacion ? _cotizacionRepuesto : "No"}\n'
        'Backup: ${_motivoNoBackup.isEmpty ? "Sí" : "No - $_motivoNoBackup"}';
    try {
      final res = await http.post(
        Uri.parse('$API_BASE_URL/solicitudes/crear'),
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'descripcion': d,
          'lat': '4.6',
          'lon': '-74.0',
          'tipo': 'preventivo',
          'fotos': (_fotosAntes + _fotosDespues + _fotosCotizacion).join(','),
          'maquina_id': _maquinaSeleccionada['id'].toString(),
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _msg('Reporte guardado', err: false);
        Navigator.pop(context, data['solicitud_id']); // devuelve el ID
      } else {
        _msg('Error: ${res.statusCode}');
      }
    } catch (e) {
      _msg('Error: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _msg(String m, {bool err = true}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(m),
          backgroundColor: err ? Colors.red : Colors.green,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_preguntandoBackup) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_backupRealizado) {
      return const Scaffold(
        body: Center(child: Text('Debes confirmar el backup para continuar.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mantenimiento Preventivo')),
      body: _mostrandoChecklist
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Mediciones eléctricas',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...[
                    'faseNeutro',
                    'faseTierra',
                    'neutroTierra',
                    'ups',
                    'protectorVoltaje',
                  ].map(
                    (e) => TextField(
                      decoration: InputDecoration(
                        labelText: e == 'faseNeutro'
                            ? 'Fase-Neutro (V)'
                            : e == 'faseTierra'
                            ? 'Fase-Tierra (V)'
                            : e == 'neutroTierra'
                            ? 'Neutro-Tierra (V)'
                            : e == 'ups'
                            ? 'UPS (V)'
                            : 'Protector de voltaje (V)',
                      ),
                      onChanged: (v) => _mediciones[e] = v,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Observaciones adicionales',
                    ),
                    onChanged: (v) => _mediciones['observacionesExtra'] = v,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Fotos antes',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  _buildFotoLista(_fotosAntes),
                  ElevatedButton.icon(
                    onPressed: () => _tomarFoto('antes'),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Tomar foto antes'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Fotos después',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  _buildFotoLista(_fotosDespues),
                  ElevatedButton.icon(
                    onPressed: () => _tomarFoto('despues'),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Tomar foto después'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Observaciones generales',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextField(controller: _obs, maxLines: 2),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _cotDialog,
                    icon: const Icon(Icons.request_quote),
                    label: Text(
                      _requiereCotizacion
                          ? 'Cotización solicitada'
                          : 'Agregar cotización',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _enviando ? null : _guardar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE30613),
                    ),
                    child: _enviando
                        ? const CircularProgressIndicator()
                        : const Text('Guardar reporte'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: widget.maquinas.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(widget.maquinas[i]['nombre']),
                onTap: () => _seleccionarMaquina(widget.maquinas[i]),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
    );
  }
}
