# Acceso de MAU$ch con ID y contraseña

## Flujo elegido

- El acceso diario usa un ID de 3 a 24 caracteres y contraseña de al menos 12 caracteres.
- Supabase Auth conserva la identidad y su UUID. Las cajas y movimientos siguen vinculados con el mismo `auth.uid()` y las políticas RLS actuales.
- La capa Edge traduce el ID a un correo interno `@accounts.mausch.invalid`; este correo nunca se muestra ni se introduce en la app.
- Las cuentas nuevas reciben un código de recuperación de 192 bits, visible una vez. Solo se almacena su hash. Cinco códigos incorrectos bloquean la recuperación por 15 minutos; también hay límites por IP para acceso, registro y recuperación.
- El correo anterior solo aparece como opción secundaria y temporal para entrar a la cuenta vieja y vincularla. Al vincularla, se cambia su email interno y se asigna una contraseña sin cambiar el UUID ni las filas existentes.

## Archivos preparados

- `supabase/sql/mausch_id_auth.sql`: tabla de IDs, tabla de límites y funciones SQL con ejecución reservada a `service_role`.
- `supabase/functions/mausch-auth/`: alta, acceso, estado, vinculación y recuperación. La clave `service_role` queda en el entorno de Edge Functions.
- `index.html`: formularios de ID y contraseña, registro, vinculación de la cuenta previa y recuperación por código. La autorización de sincronización local se guarda por UUID de Auth, no como una marca compartida entre cuentas.

## Conservación de datos

La migración es aditiva. No borra usuarios ni altera `boxes.user_id`, `moves.user_id`, las cajas, los movimientos o sus comprobantes. Al vincular una cuenta previa, Auth mantiene el mismo UUID, por lo que siguen aplicando las relaciones y políticas existentes.

Las cajas y movimientos locales que no existan en la cuenta remota siguen requiriendo la revisión y autorización inicial que ya tiene MAU$ch. La marca de autorización es específica a cada UUID para evitar enviar datos locales a otra cuenta que use el mismo dispositivo.

## Publicación

Este código está preparado en la rama `native-app-foundation`. La migración de Supabase y el despliegue de la función requieren autorización explícita para modificar producción. La pantalla web y el acceso actual por correo deben mantenerse hasta probar el inicio de sesión con ID y la vinculación de la cuenta existente.
