# Cierre general PARTE 2 - Bloque L

Fecha: 2026-08-14

## Alcance

Migrar el backend anidado de JWT simetrico HS256/`JWT_SECRET` a RS256, alineado con la verificacion RS256 del cliente Flutter.

## Fuentes consultadas

- Auth0, Signing Algorithms: https://auth0.com/docs/get-started/applications/signing-algorithms
  - RS256 permite firmar con clave privada y verificar con clave publica.
- node-jsonwebtoken README: https://github.com/auth0/node-jsonwebtoken/blob/master/README.md
  - `jwt.sign(payload, secretOrPrivateKey, options)` acepta clave privada PEM para RSA y el algoritmo se fija en opciones.
  - Para RSA se requiere clave de al menos 2048 bits salvo configuracion insegura.
- JWT.io introduction: https://jwt.io/introduction
  - Los tokens firmados con par publico/privado certifican que quien firmo posee la clave privada.

## Implementacion

- Nuevo helper `backend/src/security/jwt_rs256.js`.
- Firma con:
  - `JWT_PRIVATE_KEY_PEM`, o
  - `JWT_PRIVATE_KEY_BASE64`, o
  - `JWT_PRIVATE_KEY_PATH`.
- Verificacion con:
  - `JWT_PUBLIC_KEY_PEM`, o
  - `JWT_PUBLIC_KEY_BASE64`, o
  - `JWT_PUBLIC_KEY_PATH`.
- `signJwt` fuerza `algorithm: 'RS256'`.
- `verifyJwt` fuerza `algorithms: ['RS256']`.
- `backend/src/routes/auth.js` usa `signJwt`/`verifyJwt`.
- `backend/src/routes/licenses.js` usa `signJwt`.
- `backend/routes/licenses.js` usa `signJwt`.
- `backend/README.md` ya documenta las variables RS256 y deja de recomendar `JWT_SECRET`.

Decision de seguridad: no se genero ni se comiteo ninguna clave real. El test genera un par RSA de desarrollo en memoria dentro del propio proceso.

## Evidencia cruda - busqueda de HS256/JWT_SECRET

Comando:

```powershell
rg "JWT_SECRET|HS256|jwt\.sign|jwt\.verify|jsonwebtoken" backend -n
```

Salida relevante:

```text
backend\src\security\jwt_rs256.js:2:const jwt = require('jsonwebtoken');
backend\src\security\jwt_rs256.js:51:  return jwt.sign(payload, privateKey(), {
backend\src\security\jwt_rs256.js:58:  return jwt.verify(token, publicKey(), {
backend\test_rs256_jwt.js:3:const jwt = require('jsonwebtoken');
backend\test_rs256_jwt.js:31:const hsToken = jwt.sign({ sub: 'user-1' }, 'legacy-secret', {
backend\test_rs256_jwt.js:32:  algorithm: 'HS256',
```

Interpretacion: `HS256` queda solo en el test negativo que comprueba que el backend rechaza tokens legacy/simetricos.

## Evidencia cruda - test RS256

Comando:

```powershell
node test_rs256_jwt.js
```

Salida:

```text
RS256 JWT test passed
```

## Evidencia cruda - chequeo sintactico Node

Comando:

```powershell
node -c src\security\jwt_rs256.js && node -c src\routes\auth.js && node -c src\routes\licenses.js && node -c routes\licenses.js
```

Salida:

```text

```

## Estado del bloque

Completo en codigo y verificacion. El backend ya no depende de `JWT_SECRET`
para autenticacion/licencias y rechaza tokens que no sean RS256. Queda
pendiente operativo externo: provisionar las claves RS256 reales fuera del repo
y configurar las variables de entorno en despliegue.

## Evidencia git backend

Commit local del backend:

```text
07fbd67 feat(auth): migrar jwt a rs256
```

Push a `main` del backend:

```text
To https://github.com/omarnetcom-hub/merkaerp-control-center-backend.git
 ! [rejected]        main -> main (fetch first)
error: failed to push some refs to 'https://github.com/omarnetcom-hub/merkaerp-control-center-backend.git'
hint: Updates were rejected because the remote contains work that you do not
hint: have locally. This is usually caused by another repository pushing to
hint: the same ref. If you want to integrate the remote changes, use
hint: 'git pull' before pushing again.
```

Decision conservadora: no se hizo force push ni rebase automatico sobre una rama
del backend que esta `ahead 48, behind 22`. Se publico el commit del bloque en
rama remota separada:

```text
git -C backend push origin HEAD:codex/backend-rs256-jwt
```

Salida:

```text
remote: 
remote: Create a pull request for 'codex/backend-rs256-jwt' on GitHub by visiting:        
remote:      https://github.com/omarnetcom-hub/merkaerp-control-center-backend/pull/new/codex/backend-rs256-jwt        
remote: 
To https://github.com/omarnetcom-hub/merkaerp-control-center-backend.git
 * [new branch]      HEAD -> codex/backend-rs256-jwt
```
