import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';
import '../config.dart';
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

  @override
  void initState() {
    super.initState();
    _cargarMaquinas();
  }

  Future<void> _cargarMaquinas() async {
    print('🔄 Cargando máquinas...');
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
        print('✅ Máquinas cargadas: ${_maquinas.length}');
      } else {
        setState(() => _cargando = false);
        print('❌ Error al cargar máquinas: ${res.statusCode}');
      }
    } catch (e) {
      print('❌ Excepción al cargar máquinas: $e');
      setState(() => _cargando = false);
    }
  }

  void _msg(String m, {bool err = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: err ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _correctivo() async {
    print('🔵 Botón Correctivo presionado');
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
    print('Tipo seleccionado: $tipo');
    if (tipo == null) return;

    if (tipo == 'remoto') {
      try {
        print('Navegando a CorrectivoRemotoScreen...');
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CorrectivoRemotoScreen(parqueadero: widget.parqueadero),
          ),
        );
        if (result is int) _solicitudActivaId = result;
        print('Resultado de remoto: $result');
      } catch (e) {
        print('❌ Error navegando a remoto: $e');
        _msg('Error al abrir la pantalla');
      }
      return;
    }

    if (_maquinas.isEmpty) {
      print('No hay máquinas disponibles');
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
    if (maq == null) {
      print('No se seleccionó máquina');
      return;
    }

    try {
      print(
        'Navegando a CorrectivoPresencialScreen con máquina: ${maq['nombre']}',
      );
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CorrectivoPresencialScreen(
            parqueadero: widget.parqueadero,
            maquina: maq,
          ),
        ),
      );
      if (result is int) _solicitudActivaId = result;
      print('Resultado de presencial: $result');
    } catch (e) {
      print('❌ Error navegando a presencial: $e');
      _msg('Error al abrir la pantalla');
    }
  }

  Future<void> _preventivo() async {
    print('🟢 Botón Preventivo presionado');
    if (_maquinas.isEmpty) {
      print('No hay máquinas disponibles');
      _msg('No hay máquinas disponibles');
      return;
    }
    try {
      print('Navegando a PreventivoScreen...');
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreventivoScreen(
            parqueadero: widget.parqueadero,
            maquinas: List<Map<String, dynamic>>.from(_maquinas),
          ),
        ),
      );
      if (result is int) _solicitudActivaId = result;
      print('Resultado de preventivo: $result');
    } catch (e) {
      print('❌ Error navegando a preventivo: $e');
      _msg('Error al abrir la pantalla');
    }
  }

  Future<void> _leerQR() async {
    print('🔴 Botón Leer QR presionado');
    try {
      final code = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QrScannerScreen()),
      );
      print('Código QR escaneado: $code');
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
          print('Navegando a CorrectivoPresencialScreen con QR...');
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CorrectivoPresencialScreen(
                parqueadero: widget.parqueadero,
                maquina: maq,
              ),
            ),
          );
          if (result is int) _solicitudActivaId = result;
        } else {
          _msg('No encontrada');
        }
      }
    } catch (e) {
      print('❌ Error en lectura QR: $e');
      _msg('Error al abrir la pantalla');
    }
  }

  Future<void> _finalizar() async {
    // ... (código de finalizar sin cambios)
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
      backgroundColor: const Color(0xFF004A99),
    ),
    body: _cargando
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _boton('Mantenimiento Correctivo', Icons.build, _correctivo),
                const SizedBox(height: 12),
                _boton(
                  'Mantenimiento Preventivo',
                  Icons.checklist,
                  _preventivo,
                ),
                const SizedBox(height: 12),
                _boton('Leer QR de máquina', Icons.qr_code_scanner, _leerQR),
                const SizedBox(height: 12),
                _boton(
                  'Finalizar labor (firma obligatoria)',
                  Icons.draw,
                  _finalizar,
                  Colors.green,
                ),
              ],
            ),
          ),
  );

  Widget _boton(
    String texto,
    IconData icon,
    VoidCallback onTap, [
    Color? color,
  ]) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(texto),
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? const Color(0xFFE30613),
        minimumSize: const Size(0, 45),
      ),
    ),
  );
}
