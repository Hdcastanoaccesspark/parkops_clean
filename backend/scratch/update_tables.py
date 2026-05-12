import os
import sys
from sqlalchemy import text

# Agregar el directorio actual al path para poder importar main
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from main import engine, Base, Solicitud, Jornada

def recrear_tablas():
    with engine.connect() as conn:
        print("Borrando tabla solicitudes (si existe)...")
        conn.execute(text("DROP TABLE IF EXISTS solicitudes CASCADE"))
        print("Borrando tabla jornadas (si existe)...")
        conn.execute(text("DROP TABLE IF EXISTS jornadas CASCADE"))
        conn.commit()
    
    print("Recreando las tablas con las nuevas relaciones ForeignKey...")
    Base.metadata.create_all(bind=engine)
    print("¡Listo! Tablas actualizadas con éxito.")

if __name__ == "__main__":
    recrear_tablas()
