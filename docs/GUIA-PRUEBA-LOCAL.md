# Guía rápida — Probar ConstructING desde cero

> Checklist de puesta en marcha para probar el proyecto (frontend Flutter + backend NestJS + Supabase).

---

## 1. Backend (API en tu PC)

```bash
cd backend
npm install
npm run start:dev        # API en http://localhost:3000
```

- `backend/.env` ya configurado con Supabase (Session Pooler `aws-0-sa-east-1.pooler.supabase.com`, usuario `postgres.<ref>`).
- La API crea el esquema solo (`synchronize: true`). Verás `Starting Nest application...` sin errores de TypeORM.
- Salir: `Ctrl+C`. El watch recompila solo al editar código.

## 2. Frontend — tres modos según lo que quieras probar

### A. Web en la notebook (rápido, para flujos sin hardware)

```bash
cd frontend
flutter pub get
flutter run -d edge --web-port=8080
```

- **Usar siempre el puerto 8080**: la caché local (IndexedDB) está atada al puerto.
- Login → Dashboard → ficha de obra → Hoja de Ruta (hitos) + evidencias.
- Limitación web desktop: la "cámara" abre el file picker del OS y el GPS depende de Windows Location (activarlo en Windows + permiso de ubicación en el navegador).

### B. Emulador Android (flujo completo: cámara + GPS + sync)

```bash
# crear el emulador (una sola vez, ya hecho con imagen android-34)
flutter emulators --launch ConstructING_Pixel

# correr apuntando al backend de la PC (10.0.2.2 = localhost de la PC)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

- Primer build lento (Gradle); luego `r` hot reload, `R` restart, `q` salir.
- **GPS del emulador**: `adb emu geo fix <longitud> <latitud>` (¡lon primero!) con las coordenadas del ancla de la obra, para que pase el guard CU-35.
- Aceptá los permisos de cámara y ubicación al capturar.

### C. Teléfono físico (USB o inalámbrica)

1. Opciones de desarrollador → Depuración USB → aceptar el diálogo del PC.
2. `flutter devices` debe listar el Android (si no: otro cable/puerto, modo MTP).
3. IP LAN de la PC (`ipconfig` → Dirección IPv4):
```bash
flutter run --dart-define=API_BASE_URL=http://TU_IP:3000
```

## 3. Datos de prueba

- Crear **obra de prueba** (CU-13) con coordenadas = donde estés (CU-15), porque la captura exige estar a ±200 m del ancla (CU-35).
- Hito de prueba (CU-23) → iniciar → certificar (CU-26/28).
- Evidencia: ficha → ícono cámara en el hito → foto/video → nota → Guardar.
- Galería + "Ver Mapa" desde el ícono de foto-librería del hito (CU-40).

## 4. Sincronización offline-first (CU-44..49)

1. Registros pendientes → ícono de nube naranja en el AppBar del dashboard.
2. Tocarlo → panel "N evidencias pendientes de subida" → **Sincronizar Ahora**.
3. Con backend arriba: nube verde + "Sincronización completa".
4. Verificar en Supabase: tablas `milestone_sync` / `evidence_sync`; binarios en `backend/uploads/evidences/`.

## 5. Pruebas de calidad (QA)

```bash
cd frontend && flutter test        # suite completa
cd frontend && flutter analyze     # análisis estático
cd backend  && npm test            # tests unitarios
```

Solo sprint 4:
```bash
cd frontend && flutter test test/evidence_capture_flow_test.dart test/sync_cu44_47_test.dart test/sync_cu48_49_test.dart
```

## 6. Errores comunes

| Síntoma | Causa | Solución |
|---|---|---|
| `ENOTFOUND db.xxx.supabase.co` | Host directo IPv6-único | Ya migrado al pooler; verificar `backend/.env` |
| `ECONNREFUSED 127.0.0.1:5432` | Sin Postgres local | Usar Supabase o `docker compose up -d` |
| Login falla desde emulador/teléfono | Backend no alcanzable | `--dart-define=API_BASE_URL=http://<IP>:3000` (emulador: `10.0.2.2`) |
| Los hitos "desaparecen" en web | Cambió el puerto de flutter run | Usar siempre `--web-port=8080` |
| No aparece el dispositivo Android | Depuración USB off / cable solo-carga | Opciones de desarrollador + otro cable |
| "Se encuentra fuera de los límites" | Captura lejos del ancla CU-15 | Crear/editar obra con coordenadas actuales |
| "Mapa no disponible en modo offline" | Sin conectividad (CU-40 Alt.) | Volver a online para los tiles |

## 7. Enlaces

- Backend API: `http://localhost:3000` — health: `GET /health`
- Correos de prueba (Ethereal): https://ethereal.email/login
- Supabase dashboard: https://supabase.com/dashboard
