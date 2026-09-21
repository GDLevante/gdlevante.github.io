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

7. Desactiva el registro público si solo administración puede crear usuarios. Si mantienes invitaciones, exige confirmación de correo.

### Activar sesiones anónimas y Turnstile

El formulario público usa una sesión anónima temporal para que cada persona solo pueda subir archivos dentro de su propia carpeta.

1. Crea un widget en Cloudflare Turnstile para `gdlevante.github.io`.
2. Guarda la **site key** pública y la **secret key** privada.
3. En Supabase abre **Authentication → Providers → Anonymous Sign-Ins** y actívalo.
4. En **Authentication → Bot and Abuse Protection → CAPTCHA** selecciona Cloudflare Turnstile e introduce la secret key.
5. Mantén límites de autenticación conservadores y revisa periódicamente los usuarios anónimos antiguos.
6. Introduce únicamente la site key pública en `config.js`. La secret key nunca va al repositorio.

## 5. Conectar la web

1. En Supabase abre **Project Settings → API**.
2. Copia la URL del proyecto y la clave pública `anon`.
3. Copia `config.example.js` sobre `config.js`.
4. Introduce la URL, la clave pública y la clave pública de Turnstile.
5. Confirma los cambios y súbelos a GitHub.

No introduzcas la `service_role` en `config.js`.

La web no incorpora modo demo: si falta cualquiera de los tres valores públicos, muestra un aviso de configuración y no inventa datos ni usuarios.

## 6. Crear el primer superadministrador

1. En **Authentication → Users**, crea el usuario propietario.
2. Abre **Table Editor → profiles**.
3. Localiza el perfil con el mismo UUID.
4. Cambia:

```text
role = superadmin
approved = true
```

5. Inicia sesión y confirma que aparece la pestaña **Gestión**.

## 7. Alta y aprobación de buzos

El superadministrador crea o invita al usuario desde Supabase. Después actualiza su perfil:

```text
role = diver
approved = true
```

Las cuentas no aprobadas no obtienen acceso operativo aunque puedan autenticarse.

## 8. Correo a levante@ghostdivingspains.org

La función `notify-report` envía una notificación sin incluir coordenadas ni datos personales en el correo.

1. Crea una cuenta en Resend o sustituye el proveedor en la función por otro servicio HTTPS.
2. Verifica un dominio remitente.
3. Instala Supabase CLI.
4. Enlaza el proyecto:

```bash
supabase login
supabase link --project-ref TU_PROJECT_REF
```

5. Configura secretos:

```bash
supabase secrets set RESEND_API_KEY=TU_CLAVE
supabase secrets set MAIL_FROM="Ghost Diving Levante <avisos@tudominio.org>"
supabase secrets set MAIL_TO="levante@ghostdivingspains.org"
supabase secrets set ALLOWED_ORIGIN="https://gdlevante.github.io"
```

6. Despliega:

```bash
supabase functions deploy notify-report
```

7. Envía un reporte de prueba y confirma la llegada a `levante@ghostdivingspains.org`.

Para recibir esta notificación no hace falta la contraseña del buzón OVH. Resend entrega el mensaje a esa dirección como a cualquier destinatario. No uses el puerto 995: corresponde a POP3, es decir, recepción de correo.

### Correos de acceso y recuperación con OVH

Supabase Auth sí necesita SMTP para invitaciones y recuperación de contraseñas. Después de cambiar la contraseña que se haya compartido por un canal no seguro:

1. En Supabase abre **Project Settings → Authentication → SMTP Settings**.
2. Activa SMTP personalizado.
3. Configura el servidor saliente indicado en el panel de la cuenta OVH. Para cuentas MX Plan suele ser `ssl0.ovh.net`, puerto `465`, cifrado SSL/TLS.
4. Usuario: la dirección de correo completa.
5. Contraseña: la nueva contraseña del buzón.
6. Remitente: `levante@ghostdivingspains.org` y nombre `Ghost Diving Levante`.
7. Envía una recuperación de contraseña de prueba antes de invitar usuarios.

La contraseña SMTP se introduce solo en el panel de Supabase; nunca en `config.js`, GitHub, SQL, capturas ni documentación.

## 9. Fotografías y vídeo

Configuración inicial:

| Medio | Cantidad | Tamaño máximo | Formatos |
|---|---:|---:|---|
| Fotografía | 5 | 10 MB/unidad | JPG, PNG, WebP |
| Vídeo | 1 | 100 MB | MP4, WebM, MOV |

Los buckets no son públicos. Los administradores acceden mediante sesión autenticada y URLs firmadas temporales. Antes de publicar una fotografía o vídeo deberá activarse `publication_approved` de forma expresa.

La web utiliza carga reanudable TUS para el vídeo. Si la cobertura móvil se interrumpe, reintentará la subida por bloques de 6 MB y podrá continuar una carga previa desde el mismo dispositivo.

La subida pública está protegida mediante sesión anónima de Supabase y Turnstile. Las políticas limitan las rutas de Storage al UUID de esa sesión. Revisa también los límites de Auth y Storage después de la primera semana de uso.

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
- Turnstile o la protección elegida esté activa;
- las políticas RLS hayan pasado las pruebas de todos los roles;
- correo, recuperación de contraseña y MFA funcionen;
- exista backup verificable;
- los datos demostrativos hayan sido retirados o sustituidos;
- se haya probado desde móvil, tableta y ordenador.
