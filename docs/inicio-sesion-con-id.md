# Inicio de sesión MAU$ch con ID y contraseña

## Objetivo

La persona inicia sesión con un ID de MAU$ch y una contraseña. El correo no aparece en la pantalla de acceso ni se usa como nombre de usuario visible.

## Estado actual

- La página inicia sesión con un enlace mágico enviado por correo.
- Supabase Auth crea la identidad; las tablas `boxes` y `moves` guardan ese UUID en `user_id`.
- Ambas tablas tienen RLS y claves foráneas hacia `auth.users`.
- Las políticas y la sincronización dependen de `auth.uid()`. Ese UUID debe conservarse al cambiar el acceso.
- No hay una tabla de perfiles ni funciones Edge existentes para resolver IDs de usuario.

La autenticación por contraseña nativa de Supabase se basa en correo o teléfono; no recibe un nombre de usuario arbitrario. Para ofrecer un ID sin mostrar correos, MAU$ch necesita una capa pequeña de servidor que traduzca el ID a la identidad interna y devuelva una sesión de Auth. La clave privilegiada de Supabase debe quedarse dentro de esa función y nunca entrar al HTML ni a la app.

## Diseño propuesto

1. Crear un registro privado de inicio de sesión por cuenta: UUID de Auth, ID normalizado y el identificador interno que Auth necesita. El ID normalizado será único. La tabla tendrá RLS y permisos revocados para `anon` y `authenticated`; solo las funciones del servidor podrán consultarla.
2. Añadir una función para vincular un ID a la cuenta existente. Requiere la sesión actual de esa cuenta, fija su ID y contraseña, y conserva el mismo UUID. No copia, borra ni reasigna cajas o movimientos.
3. Añadir una función de acceso por ID. Busca la identidad interna solo en el servidor, verifica la contraseña con Supabase Auth y devuelve los tokens de sesión a la app. Los errores de ID inexistente y contraseña incorrecta deben verse iguales.
4. Añadir el alta de nuevas cuentas por ID y contraseña. La función crea la identidad de Auth y el registro privado de forma coordinada, con validación y límite de solicitudes. Las contraseñas nunca se guardan en tablas ni registros de MAU$ch.
5. La pantalla muestra el ID de MAU$ch en lugar del correo. La interfaz nunca usa metadatos modificables del usuario para decidir permisos. Las cajas y movimientos siguen autorizándose por `auth.uid()`.

## Vinculación de la cuenta existente

La cuenta actual debe vincularse mientras todavía hay una sesión válida. La función toma el UUID de esa sesión y añade el ID a esa misma cuenta. En el siguiente acceso desde Mac o iPhone, el ID debe volver a producir la misma sesión y el mismo UUID. Así se conservan las relaciones actuales con todas las cajas y movimientos.

No se debe crear otra cuenta para reemplazar la actual ni editar `user_id` en las tablas de datos.

## Decisión pendiente para la próxima sesión

Definir cómo recuperar una cuenta si se olvida la contraseña:

- correo opcional, oculto durante el acceso y usado solo para recuperación;
- código de recuperación generado al crear la cuenta y guardado por la persona;
- sin recuperación automática, con una explicación clara antes de crear el ID.

No se debe prometer recuperación por ID solamente: conocer un ID no demuestra que la cuenta pertenece a quien solicita restablecer la contraseña.

## Orden seguro de trabajo

1. Confirmar el método de recuperación.
2. Preparar la tabla privada y las funciones en un entorno de pruebas.
3. Vincular una sesión de prueba conservando el UUID y comprobar que sus cajas y movimientos siguen apareciendo.
4. Crear otra cuenta de prueba y comprobar que solo ve sus propios datos.
5. Probar contraseña incorrecta, ID duplicado, límites de intentos, cierre de sesión y recuperación.
6. Preparar la publicación y la migración gradual. Mantener el acceso actual hasta confirmar que la cuenta existente quedó vinculada.

Este documento prepara la implementación. No modifica Auth, tablas, políticas, funciones ni datos de producción.
