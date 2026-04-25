import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'correctivo_presencial_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _cargarMaquinas();
  }

  Future<void> _cargarMaquinas() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await http.get(
        Uri.parse(
          '$API_BASE_URL/parqueaderos/${widget.parqueadero['id']}/maquinas',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        setState(() {
          _maquinas = jsonDecode(response.body);
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  void _mostrarMensaje(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _correctivo() async {
    // Preguntar remoto o presencial
    final tipo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tipo de mantenimiento correctivo'),
        content: const Text('¿Es remoto o presencial?'),
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
      // Lógica remoto (por ahora solo mensaje)
      _mostrarMensaje('Mantenimiento remoto (próximamente)', isError: false);
      return;
    }

    // Presencial: mostrar máquinas para seleccionar
    if (_maquinas.isEmpty) {
      _mostrarMensaje('No hay máquinas en este parqueadero');
      return;
    }
    final maquina = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selecciona la máquina'),
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
    if (maquina == null) return;

    // Navegar a pantalla de correctivo presencial
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CorrectivoPresencialScreen(
          parqueadero: widget.parqueadero,
          maquina: maquina,
        ),
      ),
    );
    if (result == true) {
      _mostrarMensaje('Reporte enviado', isError: false);
    }
  }

  Future<void> _preventivo() async {
    // Mostrar checklist de máquinas (similar a selección)
    if (_maquinas.isEmpty) {
      _mostrarMensaje('No hay máquinas en este parqueadero');
      return;
    }
    final maquinasSeleccionadas = <Map<String, dynamic>>[];
    // Diálogo multi-selección con checkboxes
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text(
            'Selecciona las máquinas para mantenimiento preventivo',
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: _maquinas.length,
              itemBuilder: (_, i) {
                final m = _maquinas[i];
                final seleccionada = maquinasSeleccionadas.contains(m);
                return CheckboxListTile(
                  title: Text(m['nombre']),
                  value: seleccionada,
                  onChanged: (val) {
                    setStateDialog(() {
                      if (val == true) {
                        maquinasSeleccionadas.add(m);
                      } else {
                        maquinasSeleccionadas.remove(m);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                if (maquinasSeleccionadas.isEmpty) {
                  _mostrarMensaje('Selecciona al menos una máquina');
                  return;
                }
                Navigator.pop(ctx);
                // Navegar a pantalla de preventivo con la lista
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreventivoScreen(
                      parqueadero: widget.parqueadero,
                      maquinas: maquinasSeleccionadas,
                    ),
                  ),
                );
              },
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _leerQR() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result != null) {
      // Buscar máquina por código QR
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      try {
        final response = await http.get(
          Uri.parse('$API_BASE_URL/maquinas/qr/$result'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (response.statusCode == 200) {
          final maquina = jsonDecode(response.body);
          // Verificar que pertenezca al parqueadero actual
          if (maquina['parqueadero_id'] != widget.parqueadero['id']) {
            _mostrarMensaje('Esta máquina no pertenece al parqueadero actual');
            return;
          }
          // Abrir correctivo presencial directamente
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CorrectivoPresencialScreen(
                parqueadero: widget.parqueadero,
                maquina: maquina,
              ),
            ),
          );
        } else {
          _mostrarMensaje('Máquina no encontrada');
        }
      } catch (e) {
        _mostrarMensaje('Error al buscar máquina');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.parqueadero['nombre']),
        backgroundColor: const Color(0xFF004A99),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _correctivo,
                      icon: const Icon(Icons.build),
                      label: const Text('Mantenimiento Correctivo'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _preventivo,
                      icon: const Icon(Icons.checklist),
                      label: const Text('Mantenimiento Preventivo'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _leerQR,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Leer QR de máquina'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
