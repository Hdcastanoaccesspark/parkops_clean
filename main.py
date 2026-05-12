from fastapi import FastAPI, HTTPException, Depends, Form, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Boolean, Text, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime, timedelta, timezone
import bcrypt, jwt, math, os, traceback
from fpdf import FPDF
from dotenv import load_dotenv

load_dotenv()

# ----- Configuración de base de datos -----
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///parkops.db")

if DATABASE_URL.startswith("sqlite"):
    engine = create_engine(DATABASE_URL, connect_args={'check_same_thread': False})
else:
    if DATABASE_URL.startswith("postgres://"):
        DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)
    engine = create_engine(DATABASE_URL)

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
    eps = Column(String, nullable=True)
    arl = Column(String, nullable=True)
    rh = Column(String, nullable=True)
    contacto_emergencia = Column(String, nullable=True)
    foto_perfil = Column(Text, nullable=True)

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
    fecha_creacion = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    fecha_asignacion = Column(DateTime, nullable=True)
    fecha_aceptacion = Column(DateTime, nullable=True)
    fecha_inicio = Column(DateTime, nullable=True)
    fecha_fin = Column(DateTime, nullable=True)
    fotos = Column(Text, nullable=True)
    videos = Column(Text, nullable=True)
    items = Column(Text, nullable=True)
    firma = Column(Text, nullable=True)
    pdf_path = Column(String, nullable=True)
    origen = Column(String, default='cliente')  # 'cliente' o 'tecnico'

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

Base.metadata.create_all(bind=engine)

# ----- Seed de datos inicial -----
def seed_database():
    db = SessionLocal()
    try:
        if db.query(User).count() == 0:
            usuarios = [
                {"email": "cliente@test.com", "password": "1234", "rol": "cliente", "nombre": "Cliente Demo"},
                {"email": "tecnico1@test.com", "password": "1234", "rol": "tecnico", "nombre": "Tecnico Juan", "eps": "Nueva EPS", "arl": "Positiva", "rh": "O+", "contacto_emergencia": "Maria Perez - 3111234567"},
                {"email": "tecnico2@test.com", "password": "1234", "rol": "tecnico", "nombre": "Tecnico Maria", "eps": "Sanitas", "arl": "Sura", "rh": "A-", "contacto_emergencia": "Luis Rodriguez - 3109876543"},
                {"email": "coordinador@test.com", "password": "1234", "rol": "coordinador", "nombre": "Coord Ana"},
                {"email": "lider@test.com", "password": "1234", "rol": "lider", "nombre": "Lider Carlos"},
            ]
            for u in usuarios:
                hashed = bcrypt.hashpw(u["password"].encode(), bcrypt.gensalt())
                db.add(User(email=u["email"], password=hashed.decode(), rol=u["rol"], nombre=u["nombre"],
                            eps=u.get("eps"), arl=u.get("arl"), rh=u.get("rh"), contacto_emergencia=u.get("contacto_emergencia")))
            db.commit()

        if db.query(Parqueadero).count() == 0:
            p1 = Parqueadero(nombre="Parqueadero Centro", direccion="Calle 19 # 5-30", lat=4.598, lon=-74.071, ciudad="Bogotá")
            p2 = Parqueadero(nombre="Centro Comercial Unicentro", direccion="Cra 68 # 90-12", lat=4.676, lon=-74.077, ciudad="Bogotá")
            p3 = Parqueadero(nombre="Parqueadero El Dorado", direccion="Av. El Dorado", lat=4.701, lon=-74.146, ciudad="Bogotá")
            p4 = Parqueadero(nombre="Parqueadero Chapinero", direccion="Calle 45 # 15-80", lat=4.641, lon=-74.065, ciudad="Bogotá")
            p5 = Parqueadero(nombre="Parqueadero Salitre", direccion="Calle 24 # 60-10", lat=4.653, lon=-74.104, ciudad="Bogotá")
            db.add_all([p1, p2, p3, p4, p5])
            db.commit()
            config = [
                {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
                {"validador_tipo": "QR", "dispensador_tipo": "Papel"},
                {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
                {"validador_tipo": "QR", "dispensador_tipo": "Tarjeta"},
                {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
            ]
            maquinas = []
            for idx, p in enumerate([p1, p2, p3, p4, p5]):
                i = idx + 1
                cfg = config[idx]
                maquinas.append(Maquina(codigo_qr=f"VAL_{i:03d}", nombre=f"Validador {cfg['validador_tipo']}", tipo="Validador", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"DISP_{i:03d}", nombre=f"Dispensador {cfg['dispensador_tipo']}", tipo="Dispensador", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"BAR_ENT_{i:03d}", nombre=f"Barrera Entrada {i}", tipo="Barrera", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"BAR_SAL_{i:03d}", nombre=f"Barrera Salida {i}", tipo="Barrera", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"CAM_LAT1_{i:03d}", nombre=f"Cámara Lateral 1", tipo="Camara", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"CAM_LAT2_{i:03d}", nombre=f"Cámara Lateral 2", tipo="Camara", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"CAM_PISO_{i:03d}", nombre=f"Cámara de Piso", tipo="Camara", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"LPR_ENT_{i:03d}", nombre=f"LPR Entrada {i}", tipo="LPR", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"LPR_SAL_{i:03d}", nombre=f"LPR Salida {i}", tipo="LPR", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"CAJ_{i:03d}", nombre=f"Cajero {i}", tipo="Cajero", parqueadero_id=p.id))
            db.add_all(maquinas)
            db.commit()
    except Exception as e:
        print(f"Error seeding database: {e}")
        db.rollback()
    finally:
        db.close()

seed_database()

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

def generar_pdf(solicitud_id: int):
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    if not solicitud:
        db.close()
        raise HTTPException(404, "Solicitud no encontrada")
    cliente = db.query(User).filter(User.id == solicitud.cliente_id).first()
    tecnico = db.query(User).filter(User.id == solicitud.tecnico_id).first() if solicitud.tecnico_id else None
    db.close()
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Arial", size=12)
    pdf.cell(200, 10, txt="ParkOps - Reporte de Servicio", ln=True, align='C')
    pdf.ln(10)
    pdf.set_font("Arial", size=10)
    pdf.cell(200, 8, txt=f"ID Solicitud: {solicitud_id}", ln=True)
    pdf.cell(200, 8, txt=f"Cliente: {cliente.nombre if cliente else 'N/A'}", ln=True)
    pdf.cell(200, 8, txt=f"Tecnico: {tecnico.nombre if tecnico else 'N/A'}", ln=True)
    pdf.cell(200, 8, txt=f"Tipo: {solicitud.tipo}", ln=True)
    pdf.cell(200, 8, txt=f"Descripcion: {solicitud.descripcion[:150]}...", ln=True)
    pdf.cell(200, 8, txt=f"Estado: {solicitud.estado}", ln=True)
    if solicitud.fotos:
        fotos_list = [f for f in solicitud.fotos.split(',') if f]
        pdf.cell(200, 8, txt=f"Fotos adjuntas: {len(fotos_list)}", ln=True)
    pdf.cell(200, 8, txt=f"Fecha: {solicitud.fecha_creacion} a {solicitud.fecha_fin}", ln=True)
    if solicitud.firma:
        pdf.ln(5)
        pdf.cell(200, 8, txt="Firma digital registrada", ln=True)
    pdf.output(f"/tmp/solicitud_{solicitud_id}.pdf")
    return f"/tmp/solicitud_{solicitud_id}.pdf"

# --------------------- ENDPOINTS ------------------------
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
    token = jwt.encode({"user_id": user.id, "rol": user.rol, "exp": datetime.now(timezone.utc) + timedelta(hours=24)}, SECRET_KEY)
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
    return {
        "id": usuario.id, "nombre": usuario.nombre, "email": usuario.email, "rol": usuario.rol,
        "eps": usuario.eps, "arl": usuario.arl, "rh": usuario.rh,
        "contacto_emergencia": usuario.contacto_emergencia, "foto_perfil": usuario.foto_perfil
    }

@app.post("/solicitudes/crear")
def crear_solicitud(
    descripcion: str = Form(...), lat: float = Form(...), lon: float = Form(...),
    tipo: str = Form(...), fotos: str = Form(""), videos: str = Form(""),
    maquina_id: str = Form(None), user=Depends(get_current_user)):
    try:
        if user.rol not in ['cliente', 'tecnico']:
            raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        # Determinar origen
        origen = 'cliente' if user.rol == 'cliente' else 'tecnico'
        tecnicos = db.query(User).filter(User.rol == 'tecnico', User.disponible == True).all()
        if tecnicos and origen == 'cliente':
            tecnico = min(tecnicos, key=lambda t: distancia(lat, lon, t.lat or 0, t.lon or 0))
            estado = 'asignada'
            fecha_asignacion = datetime.now(timezone.utc)
        else:
            tecnico = None
            estado = 'pendiente'
            fecha_asignacion = None
        maq_id = None
        if maquina_id and maquina_id.strip() and maquina_id != 'None':
            try: maq_id = int(maquina_id)
            except: pass
        solicitud = Solicitud(
            cliente_id=user.id, descripcion=descripcion, lat=lat, lon=lon, tipo=tipo,
            estado=estado, tecnico_id=tecnico.id if tecnico else None,
            maquina_id=maq_id, fecha_asignacion=fecha_asignacion,
            fotos=fotos, videos=videos, origen=origen)
        db.add(solicitud)
        db.commit()
        solicitud_id = solicitud.id
        tecnico_nombre = tecnico.nombre if tecnico else None
        db.close()
        return {"mensaje": "Solicitud creada", "tecnico": tecnico_nombre or "Pendiente de asignación", "solicitud_id": solicitud_id}
    except HTTPException:
        raise
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, f"Error al crear solicitud: {str(e)}")

@app.get("/api/solicitudes")
def listar_solicitudes(user=Depends(get_current_user)):
    try:
        db = SessionLocal()
        if user.rol == 'cliente':
            solicitudes = db.query(Solicitud).filter(Solicitud.cliente_id == user.id).all()
        elif user.rol == 'tecnico':
            # Pendientes (sin técnico) y las que él creó (origen='tecnico') o asignadas a él
            solicitudes = db.query(Solicitud).filter(
                (Solicitud.estado == 'pendiente') |
                (Solicitud.tecnico_id == user.id) |
                (Solicitud.origen == 'tecnico')   # sus propios reportes
            ).all()
        else:
            solicitudes = db.query(Solicitud).all()
        db.close()
        result = []
        for s in solicitudes:
            cliente_nombre = None
            if s.cliente_id:
                db2 = SessionLocal()
                cliente = db2.query(User).filter(User.id == s.cliente_id).first()
                if cliente: cliente_nombre = cliente.nombre
                db2.close()
            result.append({
                "id": s.id, "descripcion": s.descripcion, "estado": s.estado, "tipo": s.tipo,
                "cliente_nombre": cliente_nombre, "tecnico_id": s.tecnico_id,
                "origen": s.origen
            })
        return result
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, f"Error al listar solicitudes: {str(e)}")

@app.post("/tecnico/iniciar_jornada")
def iniciar_jornada(lat: float = Form(...), lon: float = Form(...), user=Depends(get_current_user)):
    try:
        if user.rol != 'tecnico': raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        if db.query(Jornada).filter(Jornada.tecnico_id == user.id, Jornada.fin == None).first():
            db.close(); raise HTTPException(400, "Ya hay jornada activa")
        nueva = Jornada(tecnico_id=user.id, inicio=datetime.now(timezone.utc), lat_inicio=lat, lon_inicio=lon)
        user.disponible = True; user.lat, user.lon = lat, lon
        db.add(nueva); db.commit(); db.close()
        return {"mensaje": "Jornada iniciada"}
    except Exception as e:
        raise HTTPException(500, f"Error al iniciar jornada: {str(e)}")

@app.post("/tecnico/finalizar_jornada")
def finalizar_jornada(lat: float = Form(...), lon: float = Form(...), user=Depends(get_current_user)):
    try:
        if user.rol != 'tecnico': raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        jornada = db.query(Jornada).filter(Jornada.tecnico_id == user.id, Jornada.fin == None).first()
        if not jornada: db.close(); raise HTTPException(404, "No hay jornada activa")
        jornada.fin = datetime.now(timezone.utc); jornada.lat_fin, jornada.lon_fin = lat, lon
        user.disponible = False; db.commit(); db.close()
        return {"mensaje": "Jornada finalizada"}
    except Exception as e:
        raise HTTPException(500, f"Error al finalizar jornada: {str(e)}")

@app.post("/tecnico/aceptar/{solicitud_id}")
def aceptar_solicitud(solicitud_id: int, user=Depends(get_current_user)):
    try:
        if user.rol != 'tecnico': raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        # Permitir aceptar solicitudes pendientes (sin técnico) o las asignadas a él
        solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
        if not solicitud or solicitud.estado not in ['pendiente', 'asignada']:
            db.close(); raise HTTPException(404, "Solicitud no válida")
        if solicitud.tecnico_id is not None and solicitud.tecnico_id != user.id:
            db.close(); raise HTTPException(403, "Esta solicitud ya tiene otro técnico")
        # Si está pendiente, asignarla a este técnico
        if solicitud.estado == 'pendiente':
            solicitud.tecnico_id = user.id
        solicitud.estado = 'aceptada'
        solicitud.fecha_aceptacion = datetime.now(timezone.utc)
        user.estado = 'ocupado'
        db.commit()
        db.close()
        return {"mensaje": "Solicitud aceptada"}
    except Exception as e:
        raise HTTPException(500, f"Error al aceptar: {str(e)}")

@app.post("/tecnico/iniciar_servicio/{solicitud_id}")
def iniciar_servicio(solicitud_id: int, lat: float = Form(...), lon: float = Form(...), user=Depends(get_current_user)):
    try:
        if user.rol != 'tecnico': raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id, Solicitud.tecnico_id == user.id).first()
        if not solicitud or solicitud.estado != 'aceptada':
            db.close(); raise HTTPException(404, "Solicitud no aceptada")
        solicitud.estado = 'en_proceso'; solicitud.fecha_inicio = datetime.now(timezone.utc)
        user.estado = 'en_servicio'; db.commit(); db.close()
        return {"mensaje": "Servicio iniciado"}
    except Exception as e:
        raise HTTPException(500, f"Error al iniciar servicio: {str(e)}")

@app.post("/tecnico/cerrar_solicitud/{solicitud_id}")
def cerrar_solicitud(solicitud_id: int, items: str = Form(...), firma: str = Form(...), user=Depends(get_current_user)):
    try:
        if user.rol != 'tecnico': raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id, Solicitud.tecnico_id == user.id).first()
        if not solicitud or solicitud.estado != 'en_proceso':
            db.close(); raise HTTPException(404, "Solicitud no en proceso")
        solicitud.estado = 'finalizada'; solicitud.items = items; solicitud.firma = firma
        solicitud.fecha_fin = datetime.now(timezone.utc); user.estado = 'libre'
        try:
            pdf_path = generar_pdf(solicitud_id)
            solicitud.pdf_path = pdf_path
        except Exception as e:
            print(f"Error generando PDF: {e}")
        db.commit()
        db.close()
        return {"mensaje": "Servicio finalizado, PDF generado"}
    except Exception as e:
        raise HTTPException(500, f"Error al cerrar solicitud: {str(e)}")

@app.get("/reporte/{solicitud_id}/pdf")
def descargar_pdf(solicitud_id: int, user=Depends(get_current_user)):
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    if not solicitud:
        db.close(); raise HTTPException(404, "Solicitud no encontrada")
    if solicitud.pdf_path and os.path.exists(solicitud.pdf_path):
        db.close()
        return FileResponse(solicitud.pdf_path, media_type='application/pdf', filename=f'reporte_{solicitud_id}.pdf')
    pdf_path = generar_pdf(solicitud_id)
    solicitud.pdf_path = pdf_path
    db.commit()
    db.close()
    return FileResponse(pdf_path, media_type='application/pdf', filename=f'reporte_{solicitud_id}.pdf')

@app.get("/tecnicos")
def listar_tecnicos(user=Depends(get_current_user)):
    db = SessionLocal()
    tecnicos = db.query(User).filter(User.rol == 'tecnico').all()
    db.close()
    return [{"id": t.id, "nombre": t.nombre, "disponible": t.disponible} for t in tecnicos]

@app.put("/solicitudes/{solicitud_id}/asignar")
def asignar_tecnico(solicitud_id: int, tecnico_id: int = Form(...), user=Depends(get_current_user)):
    if user.rol not in ['coordinador', 'lider']:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    if not solicitud:
        db.close(); raise HTTPException(404, "Solicitud no encontrada")
    if solicitud.estado not in ['pendiente', 'asignada']:
        db.close(); raise HTTPException(400, "La solicitud ya fue aceptada o finalizada")
    tecnico = db.query(User).filter(User.id == tecnico_id, User.rol == 'tecnico').first()
    if not tecnico:
        db.close(); raise HTTPException(404, "Técnico no encontrado")
    solicitud.tecnico_id = tecnico_id
    solicitud.estado = 'asignada'
    solicitud.fecha_asignacion = datetime.now(timezone.utc)
    db.commit()
    db.close()
    return {"mensaje": f"Solicitud asignada a {tecnico.nombre}"}

@app.put("/solicitudes/{solicitud_id}/reasignar")
def reasignar_tecnico(solicitud_id: int, nuevo_tecnico_id: int = Form(...), user=Depends(get_current_user)):
    if user.rol not in ['coordinador', 'lider']:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    if not solicitud:
        db.close(); raise HTTPException(404, "Solicitud no encontrada")
    if solicitud.estado in ['finalizada', 'cancelada']:
        db.close(); raise HTTPException(400, "No se puede reasignar una solicitud finalizada")
    nuevo_tec = db.query(User).filter(User.id == nuevo_tecnico_id, User.rol == 'tecnico').first()
    if not nuevo_tec:
        db.close(); raise HTTPException(404, "Técnico no encontrado")
    solicitud.tecnico_id = nuevo_tecnico_id
    solicitud.estado = 'asignada'
    solicitud.fecha_asignacion = datetime.now(timezone.utc)
    db.commit()
    db.close()
    return {"mensaje": f"Solicitud reasignada a {nuevo_tec.nombre}"}

@app.post("/tecnico/devolver_a_pendiente/{solicitud_id}")
def devolver_a_pendiente(solicitud_id: int, motivo: str = Form(...), user=Depends(get_current_user)):
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id, Solicitud.tecnico_id == user.id).first()
    if not solicitud or solicitud.estado != 'aceptada':
        db.close(); raise HTTPException(400, "La solicitud no está aceptada o no te pertenece")
    solicitud.estado = 'pendiente'
    db.commit()
    db.close()
    return {"mensaje": "Solicitud devuelta a pendiente"}

@app.delete("/solicitudes/{solicitud_id}")
def cancelar_solicitud(solicitud_id: int, user=Depends(get_current_user)):
    if user.rol not in ['coordinador', 'lider']:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    if not solicitud:
        db.close(); raise HTTPException(404, "Solicitud no encontrada")
    if solicitud.estado in ['finalizada', 'cancelada']:
        db.close(); raise HTTPException(400, "No se puede cancelar una solicitud en estado final")
    solicitud.estado = 'cancelada'
    db.commit()
    db.close()
    return {"mensaje": "Solicitud cancelada"}

@app.get("/parqueaderos")
def listar_parqueaderos(user=Depends(get_current_user)):
    try:
        db = SessionLocal()
        parques = db.query(Parqueadero).all()
        db.close()
        return [{"id": p.id, "nombre": p.nombre, "direccion": p.direccion, "lat": p.lat, "lon": p.lon, "ciudad": p.ciudad} for p in parques]
    except Exception as e:
        raise HTTPException(500, f"Error: {str(e)}")

@app.get("/parqueaderos/{parqueadero_id}/maquinas")
def listar_maquinas(parqueadero_id: int, user=Depends(get_current_user)):
    try:
        db = SessionLocal()
        maquinas = db.query(Maquina).filter(Maquina.parqueadero_id == parqueadero_id).all()
        db.close()
        return [{"id": m.id, "nombre": m.nombre, "tipo": m.tipo, "codigo_qr": m.codigo_qr} for m in maquinas]
    except Exception as e:
        raise HTTPException(500, f"Error: {str(e)}")

@app.get("/maquinas/qr/{codigo_qr}")
def buscar_maquina_por_qr(codigo_qr: str, user=Depends(get_current_user)):
    try:
        db = SessionLocal()
        maquina = db.query(Maquina).filter(Maquina.codigo_qr == codigo_qr).first()
        db.close()
        if not maquina: raise HTTPException(404, "Máquina no encontrada")
        return {"id": maquina.id, "nombre": maquina.nombre, "tipo": maquina.tipo, "parqueadero_id": maquina.parqueadero_id}
    except Exception as e:
        raise HTTPException(500, f"Error: {str(e)}")

@app.get("/tecnico/jornada_activa")
def jornada_activa(user=Depends(get_current_user)):
    try:
        if user.rol != 'tecnico': raise HTTPException(403)
        db = SessionLocal()
        activa = db.query(Jornada).filter(Jornada.tecnico_id == user.id, Jornada.fin == None).first()
        db.close()
        return {"activa": activa is not None}
    except Exception as e:
        raise HTTPException(500, f"Error: {str(e)}")

# ---------- NUEVOS ENDPOINTS ----------
@app.get("/parqueaderos/{parqueadero_id}/reportes")
def reportes_por_parqueadero(parqueadero_id: int, user=Depends(get_current_user)):
    """
    Endpoint de Keyshell: reportes finalizados del técnico en ese parqueadero.
    """
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

@app.get("/tecnico/mis_reportes")
def mis_reportes_tecnico(parqueadero_id: int, user=Depends(get_current_user)):
    """
    Reportes creados por el técnico (origen='tecnico') en el parqueadero, sin importar estado.
    """
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    reportes = db.query(Solicitud).filter(
        Solicitud.cliente_id == user.id,  # el técnico "cliente" de su propio reporte
        Solicitud.origen == 'tecnico',
        Solicitud.maquina_id.in_(
            db.query(Maquina.id).filter(Maquina.parqueadero_id == parqueadero_id)
        )
    ).order_by(Solicitud.fecha_creacion.desc()).all()
    db.close()
    return [{"id": r.id, "descripcion": r.descripcion, "estado": r.estado, "tipo": r.tipo} for r in reportes]

@app.post("/admin/insertar_datos_prueba")
def insertar_datos_prueba(user=Depends(get_current_user)):
    if user.rol not in ["lider", "coordinador"]:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    db.query(Maquina).delete()
    db.query(Parqueadero).delete()
    db.commit()
    p1 = Parqueadero(nombre="Parqueadero Centro", direccion="Calle 19 # 5-30", lat=4.598, lon=-74.071, ciudad="Bogotá")
    p2 = Parqueadero(nombre="Centro Comercial Unicentro", direccion="Cra 68 # 90-12", lat=4.676, lon=-74.077, ciudad="Bogotá")
    p3 = Parqueadero(nombre="Parqueadero El Dorado", direccion="Av. El Dorado", lat=4.701, lon=-74.146, ciudad="Bogotá")
    p4 = Parqueadero(nombre="Parqueadero Chapinero", direccion="Calle 45 # 15-80", lat=4.641, lon=-74.065, ciudad="Bogotá")
    p5 = Parqueadero(nombre="Parqueadero Salitre", direccion="Calle 24 # 60-10", lat=4.653, lon=-74.104, ciudad="Bogotá")
    db.add_all([p1, p2, p3, p4, p5])
    db.commit()
    config = [
        {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
        {"validador_tipo": "QR", "dispensador_tipo": "Papel"},
        {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
        {"validador_tipo": "QR", "dispensador_tipo": "Tarjeta"},
        {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
    ]
    maquinas = []
    for idx, p in enumerate([p1, p2, p3, p4, p5]):
        i = idx + 1
        cfg = config[idx]
        maquinas.append(Maquina(codigo_qr=f"VAL_{i:03d}", nombre=f"Validador {cfg['validador_tipo']}", tipo="Validador", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"DISP_{i:03d}", nombre=f"Dispensador {cfg['dispensador_tipo']}", tipo="Dispensador", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"BAR_ENT_{i:03d}", nombre=f"Barrera Entrada {i}", tipo="Barrera", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"BAR_SAL_{i:03d}", nombre=f"Barrera Salida {i}", tipo="Barrera", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"CAM_LAT1_{i:03d}", nombre=f"Cámara Lateral 1", tipo="Camara", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"CAM_LAT2_{i:03d}", nombre=f"Cámara Lateral 2", tipo="Camara", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"CAM_PISO_{i:03d}", nombre=f"Cámara de Piso", tipo="Camara", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"LPR_ENT_{i:03d}", nombre=f"LPR Entrada {i}", tipo="LPR", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"LPR_SAL_{i:03d}", nombre=f"LPR Salida {i}", tipo="LPR", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"CAJ_{i:03d}", nombre=f"Cajero Automático {i}", tipo="Cajero", parqueadero_id=p.id))
    db.add_all(maquinas)
    db.commit()
    num_parques = db.query(Parqueadero).count()
    num_maquinas = db.query(Maquina).count()
    db.close()
    return {"mensaje": f"Insertados {num_parques} parqueaderos y {num_maquinas} máquinas"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=10000)
