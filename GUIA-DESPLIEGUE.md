# Guía de despliegue · Ghost Diving Levante

## 1. Arquitectura

La web se publica en `gdlevante.github.io`. GitHub Pages sirve el frontal estático. Supabase proporciona PostgreSQL, autenticación, almacenamiento privado y funciones de backend.

```text
Visitante / buzo / admin
          │
          ▼
GitHub Pages ─────► Supabase Auth
          │        Supabase PostgreSQL + RLS
          │        Supabase Storage privado
          └──────► Edge Function ─────► correo de aviso
```

Nunca guardes `SUPABASE_SERVICE_ROLE_KEY`, contraseñas ni claves de correo en GitHub Pages. La clave `anon` es pública por diseño; la protección la proporcionan las políticas RLS.

## 2. Requisitos

- cuenta de GitHub;
- organización o usuario de GitHub llamado `gdlevante`;
- proyecto de Supabase en región europea;
- dominio verificado para el remitente de correo;
- Git instalado para el procedimiento por terminal;
- datos legales definitivos de la asociación.

## 3. Crear el repositorio

1. En GitHub crea un repositorio público llamado exactamente `gdlevante.github.io`.
2. No añadas README ni plantilla desde GitHub si vas a subir directamente este paquete.
3. Descomprime el ZIP y abre una terminal dentro de `ghost-diving-levante`.
4. Ejecuta:

```bash
git init
git branch -M main
git add .
git commit -m "Primera versión Ghost Diving Levante"
git remote add origin https://github.com/gdlevante/gdlevante.github.io.git
git push -u origin main
```

5. En **Settings → Pages → Build and deployment**, selecciona **GitHub Actions**.
6. La acción incluida publicará la web.

## 4. Crear Supabase

1. Crea un proyecto nuevo y elige una región de la Unión Europea.
2. Guarda la contraseña de PostgreSQL en un gestor de contraseñas.
3. En **SQL Editor**, abre `supabase/migrations/001_initial.sql`.
4. Ejecuta el script completo.
5. Comprueba que se han creado las tablas, tipos, vista, buckets y políticas.
6. En **Authentication → URL Configuration** añade:

```text
Site URL: https://gdlevante.github.io
Redirect URL: https://gdlevante.github.io/**
```

7. En **Authentication → Providers → Email**, desactiva **Allow new users to sign up**. Los administradores seguirán pudiendo crear e invitar usuarios desde el panel de Supabase.

### Activar sesiones anónimas del formulario

El formulario público usa una sesión anónima temporal para que cada persona solo pueda subir archivos dentro de su propia carpeta.

1. En Supabase abre **Authentication → Providers → Anonymous Sign-Ins** y actívalo.
2. No actives ningún proveedor CAPTCHA.
3. En **Authentication → Rate Limits** conserva límites bajos para los accesos anónimos.
4. Revisa periódicamente el número de usuarios anónimos y el consumo de Storage.

Sin CAPTCHA existe más riesgo de envíos automáticos. La separación por usuario, las políticas RLS, los límites de Auth y el límite de tamaño reducen el riesgo, pero no lo eliminan por completo.

Esta opción no permite crear cuentas de buzo. Genera una identidad técnica temporal utilizada exclusivamente por el formulario. Mantén el registro por correo desactivado y los accesos anónimos activados.

## 5. Conectar la web

1. En Supabase abre **Project Settings → API**.
2. Copia la URL del proyecto y la clave pública `anon`.
3. Copia `config.example.js` sobre `config.js`.
4. Introduce la URL y la clave pública de Supabase.
5. Confirma los cambios y súbelos a GitHub.

No introduzcas la `service_role` en `config.js`.

La web no incorpora modo demo: si falta alguno de los dos valores públicos, muestra un aviso de configuración y no inventa datos ni usuarios.

## 6. Crear el primer superadministrador

Si ya habías desplegado una versión anterior, ejecuta primero, una sola vez, el archivo:

```text
supabase/migrations/002_existing_install_login_fix.sql
```

Este script crea los perfiles que falten y actualiza el disparador de altas. No borra reportes, puntos, usuarios ni archivos.

1. En **Authentication → Users**, crea el usuario propietario y activa **Auto Confirm User**. Si ya lo creaste sin confirmar, el SQL siguiente también lo confirma.
2. Abre **SQL Editor**.
3. Sustituye el correo del siguiente bloque y ejecútalo. Este comando crea el perfil si falta y lo corrige si ya existe:

```sql
update auth.users
set email_confirmed_at = coalesce(email_confirmed_at, now()),
    updated_at = now()
where lower(email) = lower('TU_CORREO_DE_ADMIN');

insert into public.profiles (id, display_name, role, approved)
select id,
       coalesce(raw_user_meta_data->>'display_name', email),
       'superadmin'::public.user_role,
       true
from auth.users
where lower(email) = lower('TU_CORREO_DE_ADMIN')
on conflict (id) do update
set role = 'superadmin'::public.user_role,
    approved = true;
```

4. Comprueba el resultado:

```sql
select u.email, p.role, p.approved
from auth.users u
left join public.profiles p on p.id = u.id
where lower(u.email) = lower('TU_CORREO_DE_ADMIN');
```

Debe mostrar `superadmin` y `true`.

5. Inicia sesión y confirma que aparece la pestaña **Gestión**.

### Si al pulsar Entrar no carga la página

Comprueba estos puntos en este orden:

1. Abre `https://gdlevante.github.io/config.js` y confirma que muestra la URL real de Supabase y una clave pública real, no `TU-PROYECTO` ni `TU_CLAVE`.
2. Ejecuta la consulta de comprobación anterior y verifica que el usuario tiene perfil, `role = superadmin` y `approved = true`.
3. En **Authentication → Users**, confirma que el correo del usuario aparece como confirmado.
4. En **Authentication → URL Configuration**, confirma que `Site URL` es exactamente `https://gdlevante.github.io`.
5. Abre una ventana privada del navegador para evitar una sesión antigua guardada.
6. Revisa **Authentication → Logs** inmediatamente después de pulsar **Entrar**.
7. Si GitHub todavía sirve una versión antigua, abre **Actions**, comprueba que el último despliegue terminó correctamente y fuerza una recarga con `Ctrl+F5`.

La aplicación muestra ahora un error diferente para cada caso: credenciales incorrectas, configuración ausente, perfil inexistente o cuenta pendiente de aprobación.

## 7. Alta y aprobación de buzos

El superadministrador crea o invita al usuario desde Supabase. Después actualiza su perfil:

```text
role = diver
approved = true
```

Las cuentas no aprobadas no obtienen acceso operativo aunque puedan autenticarse.

## 8. Configurar todos los correos

Hay dos configuraciones distintas. No deben confundirse:

| Función | Sistema | Para qué sirve |
|---|---|---|
| Aviso de nuevo reporte | Edge Function + Resend | Avisa a `ghostdivinglevante@gmail.com` cuando alguien rellena el formulario |
| Recuperación de contraseña | Correo incorporado de Supabase Auth | Envía el enlace de recuperación a usuarios existentes |

El puerto `995` es POP3: únicamente sirve para descargar correo recibido. La web no lo utiliza.

### 8.1 Avisos de nuevos reportes a Gmail

La función `notify-report` envía una notificación sin incluir coordenadas ni datos personales en el correo.

La configuración más sencilla no requiere tocar OVH ni verificar un dominio:

1. Crea la cuenta de Resend utilizando `ghostdivinglevante@gmail.com`.
2. En **API Keys**, crea una clave con permiso para enviar correo y cópiala una sola vez.
3. Instala Supabase CLI y enlaza el proyecto:

```bash
supabase login
supabase link --project-ref TU_PROJECT_REF
```

4. Configura los secretos:

```bash
supabase secrets set RESEND_API_KEY=TU_CLAVE
supabase secrets set MAIL_FROM="Ghost Diving Levante <onboarding@resend.dev>"
supabase secrets set MAIL_TO="ghostdivinglevante@gmail.com"
supabase secrets set ALLOWED_ORIGIN="https://gdlevante.github.io"
```

5. Despliega la función:

```bash
supabase functions deploy notify-report
```

6. En Supabase abre **Edge Functions → notify-report → Logs**. Después envía un formulario real.
7. Comprueba que el log devuelve estado correcto y que el mensaje llega a `ghostdivinglevante@gmail.com`, incluida la carpeta de spam.

Con `onboarding@resend.dev`, Resend solo permite enviar al correo propietario de la cuenta. Por eso la cuenta de Resend debe crearse con `ghostdivinglevante@gmail.com`. No hace falta configurar OVH ni proporcionar la contraseña de Gmail.

### 8.2 Recuperación de contraseña con Supabase

No configures SMTP de OVH. La web ya utiliza directamente:

```javascript
supabase.auth.resetPasswordForEmail(...)
```

1. Deja desactivado **Allow new users to sign up**.
2. Crea cada buzo desde **Authentication → Users** y activa **Auto Confirm User**.
3. En **Authentication → URL Configuration**, mantén `https://gdlevante.github.io` como Site URL y `https://gdlevante.github.io/**` como Redirect URL.
4. En la web abre **Acceso**, escribe el correo de un usuario existente y pulsa **Recuperar contraseña**.
5. Supabase enviará el enlace con su servicio incorporado.

El correo incorporado de Supabase tiene límites bajos y está pensado para un volumen reducido. No permite que alguien se dé de alta: solo recupera la contraseña de usuarios que ya existen.

## 9. Fotografías y vídeo

Configuración inicial:

| Medio | Cantidad | Tamaño máximo | Formatos |
|---|---:|---:|---|
| Fotografía | 5 | 10 MB/unidad | JPG, PNG, WebP |
| Vídeo | 1 | 100 MB | MP4, WebM, MOV |

Los buckets no son públicos. Los administradores acceden mediante sesión autenticada y URLs firmadas temporales. Antes de publicar una fotografía o vídeo deberá activarse `publication_approved` de forma expresa.

La web utiliza carga reanudable TUS para el vídeo. Si la cobertura móvil se interrumpe, reintentará la subida por bloques de 6 MB y podrá continuar una carga previa desde el mismo dispositivo.

La subida pública utiliza una sesión anónima de Supabase. Las políticas limitan las rutas de Storage al UUID de esa sesión. Revisa los límites de Auth y Storage después de la primera semana de uso.

Los vídeos pueden contener rostros, voces, matrículas o metadatos de ubicación. La moderación debe revisar el contenido antes de cualquier publicación y eliminar metadatos cuando proceda.

## 10. Privacidad y LOPDGDD/RGPD

Antes de abrir el formulario:

- completa identidad, NIF, domicilio y contacto del responsable;
- documenta finalidad, base jurídica, destinatarios y conservación;
- firma los acuerdos de encargado del tratamiento necesarios;
- define el procedimiento de derechos y borrado;
- registra la versión de los textos aceptados;
- define plazos separados para reportes descartados, datos de contacto y medios;
- activa HTTPS, MFA para administradores y alertas de acceso;
- realiza una revisión jurídica de los textos;
- documenta y prueba el procedimiento de brechas y restauración.

No se publican automáticamente nombres, correos, teléfonos, fotografías, vídeos ni coordenadas exactas.

## 11. Dominio personalizado futuro

Cuando tengas el dominio:

1. Copia `CNAME.example` como `CNAME`.
2. Sustituye su contenido por el dominio, por ejemplo `app.ghostdivinglevante.org`.
3. En el proveedor DNS crea el registro CNAME apuntando a `gdlevante.github.io`.
4. En GitHub abre **Settings → Pages → Custom domain**.
5. Introduce el dominio y activa **Enforce HTTPS** cuando la validación finalice.
6. Añade el nuevo dominio a las URLs permitidas de Supabase Auth.

## Instalación en móvil

La web incluye un manifiesto para poder instalarla como aplicación:

- Android/Chrome: menú del navegador → **Añadir a pantalla de inicio** o **Instalar aplicación**.
- iPhone/Safari: botón **Compartir** → **Añadir a pantalla de inicio**.

La instalación no sustituye la conexión: mapas, autenticación y envío de archivos necesitan acceso a Internet. La carga del vídeo sí puede reanudarse si se interrumpe temporalmente.

## 12. Copias de seguridad

Como mínimo:

- backup diario de PostgreSQL;
- copia periódica de los buckets `report-media` y `point-media`;
- repositorio GitHub protegido con 2FA;
- prueba trimestral de restauración;
- retención definida en la política interna.

El repositorio no contiene los datos de la plataforma ni sustituye el backup de Supabase.

## 13. Pruebas obligatorias

### Público

- el mapa solo muestra puntos `public`;
- las coordenadas visibles están aproximadas;
- un reporte no aparece en el mapa;
- se validan 5 fotos y 1 vídeo con sus límites;
- el correo se recibe sin datos sensibles.

### Buzo

- accede únicamente con cuenta aprobada;
- ve puntos públicos, de buzos o asignados;
- no gestiona usuarios ni publica puntos;
- puede añadir evidencias solo donde esté autorizado.

### Administrador

- revisa reportes y sus adjuntos privados;
- convierte el reporte en punto manteniendo la trazabilidad;
- elige visibilidad `private`, `divers` o `public`;
- aprueba por separado cada medio publicable;
- gestiona buzos, estados y operaciones.

### Seguridad

- intenta consultar reportes con un usuario buzo: debe fallar;
- intenta consultar un bucket privado sin sesión: debe fallar;
- confirma que ninguna clave secreta aparece en el repositorio;
- prueba recuperación de contraseña y MFA de administradores;
- prueba límites, antiabuso, registros y restauración.

## 14. Estados operativos

```text
Reportado → Pendiente de inspección → Inspeccionado
→ Ghost Gear confirmado → Extracción programada
→ Retirado → Zona limpia
```

También existe `Descartado`. La visibilidad es independiente del estado.

## 15. Publicación final

Publica solo cuando:

- los textos legales estén completos;
- los límites de Auth y Storage estén revisados;
- las políticas RLS hayan pasado las pruebas de todos los roles;
- correo, recuperación de contraseña y MFA funcionen;
- exista backup verificable;
- los datos demostrativos hayan sido retirados o sustituidos;
- se haya probado desde móvil, tableta y ordenador.
