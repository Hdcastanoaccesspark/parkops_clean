from fastapi import FastAPI, HTTPException, Depends, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Boolean, Text, ForeignKey
from sqlalchemy.orm import declarative_base, sessionmaker, relationship
from datetime import datetime, timedelta
import bcrypt
import jwt
import math
import os

# ----- Configuración de base de datos -----
engine = create_engine('sqlite:///parkops.db', connect_args={'check_same_thread': False})
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()

# ----- Modelos -----
class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True)
    email = Column(String, unique=True)
    password = Column(String)
    rol = Column(String)
    nombre = Column(String)
    lat = Column(Float, nullable=True)
    lon = Column(Float, nullable=True)
    estado = Column(String, default='libre')
    disponible = Column(Boolean, default=False)

class Solicitud(Base):
    __tablename__ = 'solicitudes'
    id = Column(Integer, primary_key=True)
    cliente_id = Column(Integer)
    descripcion = Column(Text)
    lat = Column(Float)
    lon = Column(Float)
    tipo = Column(String)
    estado = Column(String)
    tecnico_id = Column(Integer, nullable=True)
    maquina_id = Column(Integer, nullable=True)
    fecha_creacion = Column(DateTime, default=datetime.utcnow)
    fecha_asignacion = Column(DateTime, nullable=True)
    fecha_aceptacion = Column(DateTime, nullable=True)
    fecha_inicio = Column(DateTime, nullable=True)
    fecha_fin = Column(DateTime, nullable=True)
    fotos = Column(Text, nullable=True)
    items = Column(Text, nullable=True)
    firma = Column(Text, nullable=True)

class Jornada(Base):
    __tablename__ = 'jornadas'
    id = Column(Integer, primary_key=True)
    tecnico_id = Column(Integer)
    inicio = Column(DateTime)
    fin = Column(DateTime, nullable=True)
    lat_inicio = Column(Float)
    lon_inicio = Column(Float)
    lat_fin = Column(Float, nullable=True)
    lon_fin = Column(Float, nullable=True)

class Parqueadero(Base):
    __tablename__ = 'parqueaderos'
    id = Column(Integer, primary_key=True)
    nombre = Column(String)
    direccion = Column(String)
    lat = Column(Float)
    lon = Column(Float)
    ciudad = Column(String)

class Maquina(Base):
    __tablename__ = 'maquinas'
    id = Column(Integer, primary_key=True)
    codigo_qr = Column(String, unique=True)
    nombre = Column(String)
    tipo = Column(String)
    parqueadero_id = Column(Integer, ForeignKey('parqueaderos.id'))
    lat = Column(Float, nullable=True)
    lon = Column(Float, nullable=True)

# Recrear tablas (esto puede borrar datos existentes, pero para desarrollo está bien)
Base.metadata.drop_all(bind=engine)   # ❗OPCIONAL: elimina tablas anteriores (cuidado con datos)
Base.metadata.create_all(bind=engine)

# ----- Crear usuarios de prueba (si no existen) -----
db = SessionLocal()
usuarios = [
    {"email": "cliente@test.com", "password": "1234", "rol": "cliente", "nombre": "Cliente Demo"},
    {"email": "tecnico1@test.com", "password": "1234", "rol": "tecnico", "nombre": "Tecnico Juan"},
    {"email": "tecnico2@test.com", "password": "1234", "rol": "tecnico", "nombre": "Tecnico Maria"},
    {"email": "coordinador@test.com", "password": "1234", "rol": "coordinador", "nombre": "Coord Ana"},
    {"email": "lider@test.com", "password": "1234", "rol": "lider", "nombre": "Lider Carlos"},
]
for u in usuarios:
    if not db.query(User).filter(User.email == u["email"]).first():
        hashed = bcrypt.hashpw(u["password"].encode(), bcrypt.gensalt())
        db.add(User(email=u["email"], password=hashed.decode(), rol=u["rol"], nombre=u["nombre"]))
db.commit()
db.close()

# ----- FastAPI app -----
app = FastAPI(title="ParkOps API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

SECRET_KEY = "clave_super_secreta_parkops"
security = HTTPBearer()

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=['HS256'])
        db = SessionLocal()
        user = db.query(User).filter(User.id == payload['user_id']).first()
        db.close()
        return user
    except:
        raise HTTPException(401, "Token inválido")

def distancia(lat1, lon1, lat2, lon2):
    return math.sqrt((lat1-lat2)**2 + (lon1-lon2)**2)

@app.get("/")
def root():
    return {"mensaje": "ParkOps API funcionando"}

@app.post("/auth/login")
def login(email: str = Form(...), password: str = Form(...)):
    db = SessionLocal()
    user = db.query(User).filter(User.email == email).first()
    db.close()
    if not user or not bcrypt.checkpw(password.encode(), user.password.encode()):
        raise HTTPException(401, "Credenciales incorrectas")
    token = jwt.encode({"user_id": user.id, "rol": user.rol, "exp": datetime.utcnow() + timedelta(hours=24)}, SECRET_KEY)
    return {"token": token, "rol": user.rol, "user_id": user.id}

@app.get("/usuarios/{user_id}")
def get_usuario(user_id: int, user=Depends(get_current_user)):
    if user.id != user_id and user.rol not in ['lider', 'coordinador']:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    usuario = db.query(User).filter(User.id == user_id).first()
    db.close()
    if not usuario:
        raise HTTPException(404, "Usuario no encontrado")
    return {"id": usuario.id, "nombre": usuario.nombre, "email": usuario.email, "rol": usuario.rol}

@app.post("/solicitudes/crear")
def crear_solicitud(descripcion: str = Form(...), lat: float = Form(...), lon: float = Form(...), tipo: str = Form(...), fotos: str = Form(""), maquina_id: int = Form(None), user=Depends(get_current_user)):
    if user.rol != 'cliente':
        raise HTTPException(403, "Solo clientes")
    db = SessionLocal()
    tecnicos = db.query(User).filter(User.rol == 'tecnico', User.disponible == True).all()
    if not tecnicos:
        db.close()
        raise HTTPException(404, "No hay técnicos disponibles")
    tecnico = min(tecnicos, key=lambda t: distancia(lat, lon, t.lat or 0, t.lon or 0))
    solicitud = Solicitud(
        cliente_id=user.id,
        descripcion=descripcion,
        lat=lat,
        lon=lon,
        tipo=tipo,
        estado='asignada',
        tecnico_id=tecnico.id,
        maquina_id=maquina_id,
        fecha_asignacion=datetime.utcnow(),
        fotos=fotos
    )
    db.add(solicitud)
    db.commit()
    db.close()
    return {"mensaje": "Solicitud creada", "tecnico": tecnico.nombre, "solicitud_id": solicitud.id}

@app.get("/api/solicitudes")
def listar_solicitudes(user=Depends(get_current_user)):
    db = SessionLocal()
    if user.rol == 'cliente':
        solicitudes = db.query(Solicitud).filter(Solicitud.cliente_id == user.id).all()
    elif user.rol == 'tecnico':
        solicitudes = db.query(Solicitud).filter(Solicitud.tecnico_id == user.id).all()
    else:
        solicitudes = db.query(Solicitud).all()
    db.close()
    result = []
    for s in solicitudes:
        cliente_nombre = None
        if s.cliente_id:
            db2 = SessionLocal()
            cliente = db2.query(User).filter(User.id == s.cliente_id).first()
            if cliente:
                cliente_nombre = cliente.nombre
            db2.close()
        result.append({
            "id": s.id,
            "descripcion": s.descripcion,
            "estado": s.estado,
            "tipo": s.tipo,
            "cliente_nombre": cliente_nombre
        })
    return result

@app.post("/tecnico/iniciar_jornada")
def iniciar_jornada(lat: float = Form(...), lon: float = Form(...), user=Depends(get_current_user)):
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    activa = db.query(Jornada).filter(Jornada.tecnico_id == user.id, Jornada.fin == None).first()
    if activa:
        db.close()
        raise HTTPException(400, "Ya hay jornada activa")
    nueva = Jornada(tecnico_id=user.id, inicio=datetime.utcnow(), lat_inicio=lat, lon_inicio=lon)
    user.disponible = True
    user.lat, user.lon = lat, lon
    db.add(nueva)
    db.commit()
    db.close()
    return {"mensaje": "Jornada iniciada"}

@app.post("/tecnico/finalizar_jornada")
def finalizar_jornada(lat: float = Form(...), lon: float = Form(...), user=Depends(get_current_user)):
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    jornada = db.query(Jornada).filter(Jornada.tecnico_id == user.id, Jornada.fin == None).first()
    if not jornada:
        db.close()
        raise HTTPException(404, "No hay jornada activa")
    jornada.fin = datetime.utcnow()
    jornada.lat_fin, jornada.lon_fin = lat, lon
    user.disponible = False
    db.commit()
    db.close()
    return {"mensaje": "Jornada finalizada"}

@app.post("/tecnico/aceptar/{solicitud_id}")
def aceptar_solicitud(solicitud_id: int, user=Depends(get_current_user)):
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id, Solicitud.tecnico_id == user.id).first()
    if not solicitud or solicitud.estado != 'asignada':
        db.close()
        raise HTTPException(404, "Solicitud no válida")
    solicitud.estado = 'aceptada'
    solicitud.fecha_aceptacion = datetime.utcnow()
    user.estado = 'ocupado'
    db.commit()
    db.close()
    return {"mensaje": "Solicitud aceptada"}

@app.post("/tecnico/iniciar_servicio/{solicitud_id}")
def iniciar_servicio(solicitud_id: int, lat: float = Form(...), lon: float = Form(...), user=Depends(get_current_user)):
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id, Solicitud.tecnico_id == user.id).first()
    if not solicitud or solicitud.estado != 'aceptada':
        db.close()
        raise HTTPException(404, "Solicitud no aceptada")
    solicitud.estado = 'en_proceso'
    solicitud.fecha_inicio = datetime.utcnow()
    user.estado = 'en_servicio'
    db.commit()
    db.close()
    return {"mensaje": "Servicio iniciado"}

@app.post("/tecnico/cerrar_solicitud/{solicitud_id}")
def cerrar_solicitud(solicitud_id: int, items: str = Form(...), firma: str = Form(...), user=Depends(get_current_user)):
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id, Solicitud.tecnico_id == user.id).first()
    if not solicitud or solicitud.estado != 'en_proceso':
        db.close()
        raise HTTPException(404, "Solicitud no en proceso")
    solicitud.estado = 'finalizada'
    solicitud.items = items
    solicitud.firma = firma
    solicitud.fecha_fin = datetime.utcnow()
    user.estado = 'libre'
    db.commit()
    db.close()
    return {"mensaje": "Servicio finalizado"}

# ----- Endpoints para parqueaderos y máquinas -----
@app.get("/parqueaderos")
def listar_parqueaderos(user=Depends(get_current_user)):
    db = SessionLocal()
    parques = db.query(Parqueadero).all()
    db.close()
    return [{"id": p.id, "nombre": p.nombre, "direccion": p.direccion, "lat": p.lat, "lon": p.lon, "ciudad": p.ciudad} for p in parques]

@app.get("/parqueaderos/{parqueadero_id}/maquinas")
def listar_maquinas(parqueadero_id: int, user=Depends(get_current_user)):
    db = SessionLocal()
    maquinas = db.query(Maquina).filter(Maquina.parqueadero_id == parqueadero_id).all()
    db.close()
    return [{"id": m.id, "nombre": m.nombre, "tipo": m.tipo, "codigo_qr": m.codigo_qr} for m in maquinas]

@app.get("/maquinas/qr/{codigo_qr}")
def buscar_maquina_por_qr(codigo_qr: str, user=Depends(get_current_user)):
    db = SessionLocal()
    maquina = db.query(Maquina).filter(Maquina.codigo_qr == codigo_qr).first()
    db.close()
    if not maquina:
        raise HTTPException(404, "Máquina no encontrada")
    return {"id": maquina.id, "nombre": maquina.nombre, "tipo": maquina.tipo, "parqueadero_id": maquina.parqueadero_id}

@app.get("/tecnico/jornada_activa")
def jornada_activa(user=Depends(get_current_user)):
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    activa = db.query(Jornada).filter(Jornada.tecnico_id == user.id, Jornada.fin == None).first()
    db.close()
    return {"activa": activa is not None}

@app.get("/parqueaderos/{parqueadero_id}/reportes")
def reportes_por_parqueadero(parqueadero_id: int, user=Depends(get_current_user)):
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    maquinas = db.query(Maquina).filter(Maquina.parqueadero_id == parqueadero_id).all()
    maquinas_ids = [m.id for m in maquinas]
    reportes = db.query(Solicitud).filter(
        Solicitud.tecnico_id == user.id,
        Solicitud.estado == 'finalizada',
        Solicitud.maquina_id.in_(maquinas_ids)
    ).order_by(Solicitud.fecha_fin.desc()).all()
    db.close()
    return [{
        "id": r.id,
        "descripcion": r.descripcion,
        "fecha": r.fecha_fin,
        "tipo": r.tipo,
        "maquina_nombre": next((m.nombre for m in maquinas if m.id == r.maquina_id), "")
    } for r in reportes]

# ----- Endpoint para insertar datos de prueba (solo líder/coordinador) -----
@app.post("/admin/insertar_datos_prueba")
def insertar_datos_prueba(user=Depends(get_current_user)):
    if user.rol not in ["lider", "coordinador"]:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    
    # Limpiar datos antiguos
    db.query(Maquina).delete()
    db.query(Parqueadero).delete()
    db.commit()
    
    # Crear parqueaderos
    p1 = Parqueadero(nombre="Parqueadero Centro", direccion="Calle 19 # 5-30", lat=4.598, lon=-74.071, ciudad="Bogotá")
    p2 = Parqueadero(nombre="Centro Comercial Unicentro", direccion="Cra 68 # 90-12", lat=4.676, lon=-74.077, ciudad="Bogotá")
    p3 = Parqueadero(nombre="Parqueadero El Dorado", direccion="Av. El Dorado", lat=4.701, lon=-74.146, ciudad="Bogotá")
    p4 = Parqueadero(nombre="Parqueadero Chapinero", direccion="Calle 45 # 15-80", lat=4.641, lon=-74.065, ciudad="Bogotá")
    p5 = Parqueadero(nombre="Parqueadero Salitre", direccion="Calle 24 # 60-10", lat=4.653, lon=-74.104, ciudad="Bogotá")
    db.add_all([p1, p2, p3, p4, p5])
    db.commit()
    
    # Configuración de validadores y dispensadores por parqueadero (corregida)
    # Regla: Si validador es "Tarjeta", dispensador debe ser "Tarjeta".
    config = [
        {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},   # p1
        {"validador_tipo": "QR", "dispensador_tipo": "Papel"},           # p2
        {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},    # p3 (corregido: antes era Papel)
        {"validador_tipo": "QR", "dispensador_tipo": "Tarjeta"},         # p4
        {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},    # p5
    ]
    
    maquinas = []
    for idx, p in enumerate([p1, p2, p3, p4, p5]):
        i = idx + 1
        cfg = config[idx]
        
        # 1. Validador
        validador_nombre = f"Validador {cfg['validador_tipo']}"
        maquinas.append(Maquina(codigo_qr=f"VAL_{i:03d}", nombre=validador_nombre, tipo="Validador", parqueadero_id=p.id))
        
        # 2. Dispensador
        dispensador_nombre = f"Dispensador {cfg['dispensador_tipo']}"
        maquinas.append(Maquina(codigo_qr=f"DISP_{i:03d}", nombre=dispensador_nombre, tipo="Dispensador", parqueadero_id=p.id))
        
        # 3. Barreras automáticas (entrada y salida)
        maquinas.append(Maquina(codigo_qr=f"BAR_ENT_{i:03d}", nombre=f"Barrera Entrada {i}", tipo="Barrera", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"BAR_SAL_{i:03d}", nombre=f"Barrera Salida {i}", tipo="Barrera", parqueadero_id=p.id))
        
        # 4. Cámaras de inventario (2 laterales, 1 piso)
        maquinas.append(Maquina(codigo_qr=f"CAM_LAT1_{i:03d}", nombre=f"Cámara Lateral 1", tipo="Camara", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"CAM_LAT2_{i:03d}", nombre=f"Cámara Lateral 2", tipo="Camara", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"CAM_PISO_{i:03d}", nombre=f"Cámara de Piso", tipo="Camara", parqueadero_id=p.id))
        
        # 5. LPR (entrada y salida)
        maquinas.append(Maquina(codigo_qr=f"LPR_ENT_{i:03d}", nombre=f"LPR Entrada {i}", tipo="LPR", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"LPR_SAL_{i:03d}", nombre=f"LPR Salida {i}", tipo="LPR", parqueadero_id=p.id))
        
        # 6. Cajero automático
        maquinas.append(Maquina(codigo_qr=f"CAJ_{i:03d}", nombre=f"Cajero Automático {i}", tipo="Cajero", parqueadero_id=p.id))
    
    db.add_all(maquinas)
    db.commit()
    
    num_parques = db.query(Parqueadero).count()
    num_maquinas = db.query(Maquina).count()
    db.close()
    return {"mensaje": f"Insertados {num_parques} parqueaderos y {num_maquinas} máquinas"}

# Para correr localmente
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=10000)
