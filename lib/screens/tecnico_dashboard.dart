import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import 'menu_parqueadero.dart';

class TecnicoDashboard extends StatefulWidget {
  const TecnicoDashboard({super.key});
  @override
  State<TecnicoDashboard> createState() => _TecnicoDashboardState();
}

class _TecnicoDashboardState extends State<TecnicoDashboard> {
  bool _jornadaActiva = false,
      _jornadaPausada = false,
      _cargandoJornada = false;
  List<dynamic> _parqueaderos = [], _visitasAsignadas = [];
  bool _cargandoParqueaderos = true, _cargandoVisitas = true;
  String? _errorParqueaderos, _errorVisitas;
  String? _parqueaderoLaborNombre;
  bool _laborPausada = false;
  String _vistaActual = 'parqueaderos';
  String _nombre = 'Técnico';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _cargarParqueaderos();
    _cargarVisitasAsignadas();
    _consultarEstadoJornada();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nombre = prefs.getString('nombre') ?? 'Técnico';
    });
  }

  Future<bool> _confirmar(String titulo, String mensaje) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _logout() async {
    final confirm = await _confirmar(
      'Cerrar sesión',
      '¿Está seguro de que desea cerrar sesión?',
    );
    if (!confirm) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _consultarEstadoJornada() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/tecnico/jornada_activa'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() => _jornadaActiva = data['activa'] == true);
      }
    } catch (_) {}
  }

  Future<void> _iniciarJornada() async {
    if (!await _confirmar(
      'Iniciar jornada',
      '¿Está seguro de que desea iniciar la jornada laboral?',
    ))
      return;
    setState(() => _cargandoJornada = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final res = await http.post(
        Uri.parse('$API_BASE_URL/tecnico/iniciar_jornada'),
        headers: {'Authorization': 'Bearer $token'},
        body: {'lat': pos.latitude.toString(), 'lon': pos.longitude.toString()},
      );
      if (res.statusCode == 200) {
        setState(() => _jornadaActiva = true);
        _msg('Jornada iniciada');
      } else
        _msg('Error al iniciar jornada: ${res.statusCode}');
    } catch (e) {
      _msg('Error GPS: $e');
    } finally {
      if (mounted) setState(() => _cargandoJornada = false);
    }
  }

  Future<void> _finalizarJornada() async {
    if (!await _confirmar(
      'Finalizar jornada',
      '¿Está seguro de que desea finalizar la jornada laboral?',
    ))
      return;
    setState(() => _cargandoJornada = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final res = await http.post(
        Uri.parse('$API_BASE_URL/tecnico/finalizar_jornada'),
        headers: {'Authorization': 'Bearer $token'},
        body: {'lat': pos.latitude.toString(), 'lon': pos.longitude.toString()},
      );
      if (res.statusCode == 200) {
        setState(() {
          _jornadaActiva = false;
          _jornadaPausada = false;
          _parqueaderoLaborNombre = null;
          _laborPausada = false;
        });
        _msg('Jornada finalizada');
      } else
        _msg('Error al finalizar jornada: ${res.statusCode}');
    } catch (e) {
      _msg('Error GPS: $e');
    } finally {
      if (mounted) setState(() => _cargandoJornada = false);
    }
  }

  Future<void> _pausarJornada() async {
    if (!await _confirmar('Pausar jornada', '¿Desea pausar la jornada?'))
      return;
    setState(() {
      _jornadaPausada = true;
      if (_parqueaderoLaborNombre != null) _laborPausada = true;
    });
    _msg('Jornada pausada', err: false);
  }

  Future<void> _reanudarJornada() async {
    if (!await _confirmar('Reanudar jornada', '¿Desea reanudar la jornada?'))
      return;
    setState(() {
      _jornadaPausada = false;
      if (_parqueaderoLaborNombre != null) _laborPausada = false;
    });
    _msg('Jornada reanudada', err: false);
  }

  Future<void> _cargarParqueaderos() async {
    setState(() {
      _cargandoParqueaderos = true;
      _errorParqueaderos = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      setState(() {
        _cargandoParqueaderos = false;
        _errorParqueaderos = 'Sin token';
      });
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/parqueaderos'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200)
        setState(() {
          _parqueaderos = jsonDecode(res.body);
          _cargandoParqueaderos = false;
        });
      else
        setState(() {
          _cargandoParqueaderos = false;
          _errorParqueaderos = 'HTTP ${res.statusCode}';
        });
    } catch (e) {
      setState(() {
        _cargandoParqueaderos = false;
        _errorParqueaderos = 'Error de conexión';
      });
    }
  }

  Future<void> _cargarVisitasAsignadas() async {
    setState(() {
      _cargandoVisitas = true;
      _errorVisitas = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      setState(() {
        _cargandoVisitas = false;
        _errorVisitas = 'Sin token';
      });
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/api/solicitudes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final todas = jsonDecode(res.body) as List;
        setState(() {
          _visitasAsignadas = todas
              .where(
                (s) =>
                    s['estado'] == 'asignada' ||
                    s['estado'] == 'pendiente' ||
                    s['estado'] == 'aceptada',
              )
              .toList();
          _cargandoVisitas = false;
        });
      } else
        setState(() {
          _cargandoVisitas = false;
          _errorVisitas = 'HTTP ${res.statusCode}';
        });
    } catch (e) {
      setState(() {
        _cargandoVisitas = false;
        _errorVisitas = 'Error de conexión';
      });
    }
  }

  Future<void> _aceptarSolicitud(int id) async {
    if (!_jornadaActiva) {
      _msg('Debes iniciar jornada');
      return;
    }
    if (_jornadaPausada) {
      _msg('Jornada pausada. Reanuda primero.');
      return;
    }
    if (!await _confirmar(
      'Aceptar solicitud',
      '¿Confirma que desea aceptar esta visita?',
    ))
      return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final res = await http.post(
      Uri.parse('$API_BASE_URL/tecnico/aceptar/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      _cargarVisitasAsignadas();
      _msg('Solicitud aceptada', err: false);
      // Obtener el parqueadero_id de la solicitud
      final solicitud = _visitasAsignadas.firstWhere((s) => s['id'] == id);
      final parqueaderoId = solicitud['parqueadero_id'];
      if (parqueaderoId != null && _parqueaderos.isNotEmpty) {
        final parqueadero = _parqueaderos.firstWhere(
          (p) => p['id'] == parqueaderoId,
        );
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MenuParqueaderoScreen(parqueadero: parqueadero),
          ),
        );
        _cargarParqueaderos();
        _cargarVisitasAsignadas();
      }
    } else
      _msg('Error al aceptar: ${res.statusCode}');
  }

  Future<void> _devolverAPendiente(int id) async {
    final motivoController = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Devolver a pendiente'),
        content: TextField(
          controller: motivoController,
          decoration: const InputDecoration(hintText: 'Motivo del retraso'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, motivoController.text),
            child: const Text('Devolver'),
          ),
        ],
      ),
    );
    if (motivo == null || motivo.isEmpty) {
      _msg('Debes ingresar un motivo');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final res = await http.post(
      Uri.parse('$API_BASE_URL/tecnico/devolver_a_pendiente/$id'),
      headers: {'Authorization': 'Bearer $token'},
      body: {'motivo': motivo},
    );
    if (res.statusCode == 200) {
      _cargarVisitasAsignadas();
      _msg('Solicitud devuelta a pendiente', err: false);
    } else
      _msg('Error al devolver: ${res.statusCode}');
  }

  Future<void> _entrarAParqueadero(Map<String, dynamic> p) async {
    if (!_jornadaActiva) {
      _msg('Debes iniciar jornada primero');
      return;
    }
    if (_jornadaPausada) {
      _msg('Jornada pausada');
      return;
    }
    if (!await _confirmar(
      'Iniciar labor',
      '¿Desea iniciar labor en ${p['nombre']}?',
    ))
      return;
    try {
      await Geolocator.getCurrentPosition();
    } catch (_) {}
    setState(() {
      _parqueaderoLaborNombre = p['nombre'];
      _laborPausada = false;
    });
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MenuParqueaderoScreen(parqueadero: p)),
    );
    setState(() {
      _parqueaderoLaborNombre = null;
      _laborPausada = false;
    });
    _cargarParqueaderos();
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          Image.network('https://i.imgur.com/dpfS4Xw.png', height: 40),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ParkOps - Técnico', style: TextStyle(fontSize: 16)),
              Text(_nombre, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
      backgroundColor: const Color(0xFF004A99),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: _logout,
          tooltip: 'Cerrar sesión',
        ),
        if (!_jornadaActiva)
          IconButton(
            icon: const Icon(Icons.play_arrow, color: Colors.white),
            onPressed: _cargandoJornada ? null : _iniciarJornada,
            tooltip: 'Iniciar jornada',
          ),
        if (_jornadaActiva && !_jornadaPausada)
          IconButton(
            icon: const Icon(Icons.pause, color: Colors.white),
            onPressed: _pausarJornada,
            tooltip: 'Pausar jornada',
          ),
        if (_jornadaActiva && _jornadaPausada)
          IconButton(
            icon: const Icon(Icons.play_arrow, color: Colors.white),
            onPressed: _reanudarJornada,
            tooltip: 'Reanudar jornada',
          ),
        if (_jornadaActiva)
          IconButton(
            icon: const Icon(Icons.stop, color: Colors.white),
            onPressed: _cargandoJornada ? null : _finalizarJornada,
            tooltip: 'Finalizar jornada',
          ),
      ],
    ),
    body: Column(
      children: [
        if (_parqueaderoLaborNombre != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: _laborPausada ? Colors.yellow[700] : Colors.green,
            child: Row(
              children: [
                Icon(
                  _laborPausada ? Icons.pause_circle : Icons.location_on,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _laborPausada
                        ? 'Labor pausada en $_parqueaderoLaborNombre'
                        : 'Trabajando en $_parqueaderoLaborNombre',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() => _vistaActual = 'asignadas'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _vistaActual == 'asignadas'
                        ? const Color(0xFFE30613)
                        : Colors.grey,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('Visitas Asignadas'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      setState(() => _vistaActual = 'parqueaderos'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _vistaActual == 'parqueaderos'
                        ? const Color(0xFFE30613)
                        : Colors.grey,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('Parqueaderos'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _vistaActual == 'asignadas'
              ? _cargandoVisitas
                    ? const Center(child: CircularProgressIndicator())
                    : _errorVisitas != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Error: $_errorVisitas'),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _cargarVisitasAsignadas,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : _visitasAsignadas.isEmpty
                    ? const Center(child: Text('No hay visitas asignadas.'))
                    : ListView.builder(
                        itemCount: _visitasAsignadas.length,
                        itemBuilder: (_, i) {
                          final s = _visitasAsignadas[i];
                          final bool puedeAceptar =
                              s['estado'] == 'asignada' ||
                              s['estado'] == 'pendiente';
                          final bool puedeDevolver = s['estado'] == 'aceptada';
                          return Card(
                            margin: const EdgeInsets.all(8),
                            child: ListTile(
                              title: Text(
                                'Cliente: ${s['cliente_nombre'] ?? 'N/D'}',
                              ),
                              subtitle: Text(
                                '${s['tipo']} - ${s['estado']}\n${s['descripcion']}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (puedeAceptar)
                                    ElevatedButton(
                                      onPressed:
                                          (!_jornadaActiva || _jornadaPausada)
                                          ? null
                                          : () => _aceptarSolicitud(s['id']),
                                      child: const Text('Aceptar'),
                                    ),
                                  if (puedeDevolver)
                                    TextButton(
                                      onPressed: () =>
                                          _devolverAPendiente(s['id']),
                                      child: const Text(
                                        'Devolver',
                                        style: TextStyle(color: Colors.orange),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
              : _cargandoParqueaderos
              ? const Center(child: CircularProgressIndicator())
              : _errorParqueaderos != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_errorParqueaderos'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _cargarParqueaderos,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _parqueaderos.isEmpty
              ? const Center(child: Text('No hay parqueaderos disponibles.'))
              : ListView.builder(
                  itemCount: _parqueaderos.length,
                  itemBuilder: (_, i) => Card(
                    margin: const EdgeInsets.all(8),
                    child: ListTile(
                      title: Text(_parqueaderos[i]['nombre']),
                      subtitle: Text(_parqueaderos[i]['direccion']),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: (!_jornadaActiva || _jornadaPausada)
                          ? null
                          : () => _entrarAParqueadero(_parqueaderos[i]),
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}
