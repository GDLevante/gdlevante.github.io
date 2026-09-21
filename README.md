# Ghost Diving Levante

Web pública e intranet para registrar, revisar y gestionar puntos de redes fantasma.

## Incluye

- web responsive para GitHub Pages;
- mapa público con ubicaciones moderadas;
- formulario público con hasta 5 fotos y 1 vídeo;
- login y roles `diver`, `admin` y `superadmin`;
- mapa interno y panel de gestión;
- PostgreSQL, Auth y Storage mediante Supabase;
- políticas RLS y almacenamiento privado;
- función de aviso a `levante@ghostdivingspains.org`;
- despliegue automático con GitHub Actions;
- preparación para dominio personalizado.
- interfaz móvil con navegación táctil e instalación como aplicación web;
- carga reanudable de vídeo para conexiones móviles inestables.

No existe modo de demostración: sin la configuración pública de Supabase y Turnstile la aplicación muestra un aviso y no simula datos ni accesos. La puesta en producción se explica en `GUIA-DESPLIEGUE.md`.

## Límites de medios iniciales

- fotografías: JPG, PNG o WebP; máximo 5 archivos de 10 MB;
- vídeo: MP4, WebM o MOV; máximo 1 archivo de 100 MB;
- todo el material es privado por defecto;
- la publicación requiere aprobación administrativa independiente.

## Antes de producción

Completa los datos legales, activa protección antiabuso, revisa las políticas RLS, configura copias de seguridad y realiza las pruebas de la guía.
