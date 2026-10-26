# AAA con RADIUS (NPS): Router y Switch Cisco con Active Directory

### Arlene Fernández Herrera · Matrícula: 2025-0730

**Seguridad de Redes · ITLA**

---

## 🎥 Video Demostrativo

**[▶ Ver video de demostración](https://youtu.be/REEMPLAZAR-CON-TU-ID)**

---

## 📋 Tabla de Contenido

1. [Propósito del Laboratorio](#1-propósito-del-laboratorio)
2. [Topología y Direccionamiento](#2-topología-y-direccionamiento)
3. [Diseño de seguridad AAA](#3-diseño-de-seguridad-aaa)
4. [Procedimiento paso a paso](#4-procedimiento-paso-a-paso)
   - [Paso 1. Red virtual y PNETLab](#paso-1-red-virtual-y-pnetlab)
   - [Paso 2. Servidor: red, Active Directory, grupos y usuarios](#paso-2-servidor-red-active-directory-grupos-y-usuarios)
   - [Paso 3. Servidor: NPS (RADIUS)](#paso-3-servidor-nps-radius)
   - [Paso 4. Switch: red base y VLAN de gestión](#paso-4-switch-red-base-y-vlan-de-gestión)
   - [Paso 5. Router: red base](#paso-5-router-red-base)
   - [Paso 6. Verificar la conectividad](#paso-6-verificar-la-conectividad)
   - [Paso 7. Router: usuario local, SSH y niveles de privilegio](#paso-7-router-usuario-local-ssh-y-niveles-de-privilegio)
   - [Paso 8. Router: RADIUS, AAA y logs](#paso-8-router-radius-aaa-y-logs)
   - [Paso 9. Switch: usuario local, SSH y niveles de privilegio](#paso-9-switch-usuario-local-ssh-y-niveles-de-privilegio)
   - [Paso 10. Switch: RADIUS, AAA y logs](#paso-10-switch-radius-aaa-y-logs)
   - [Paso 11. Guardar y exportar las configuraciones](#paso-11-guardar-y-exportar-las-configuraciones)
   - [Paso 12. Pruebas de verificación](#paso-12-pruebas-de-verificación)
5. [Matriz de cumplimiento de requisitos](#5-matriz-de-cumplimiento-de-requisitos)
6. [Capturas de Pantalla](#6-capturas-de-pantalla)
7. [Estructura del Repositorio](#7-estructura-del-repositorio)

---

## 1. Propósito del Laboratorio

Esta práctica implementa **autenticación, autorización y registro (AAA)** centralizados para el acceso administrativo a un **Router** y un **Switch** Cisco, usando **RADIUS** contra un **Servidor Windows Server 2022** que ejecuta **Active Directory** y **NPS (Network Policy Server)**.

* Los administradores se autentican con su cuenta de Active Directory en la **consola** y en el **puerto auxiliar**. El grupo de AD al que pertenecen define su **nivel de privilegio** en el equipo: **nivel 0, 5 o 10**.
* Cada equipo tiene un **usuario local** (respaldo si el servidor RADIUS no responde, y acceso por **SSH**).
* El acceso remoto es **solo por SSH versión 2**; Telnet queda deshabilitado.
* Toda autenticación, autorización y actividad de RADIUS queda **registrada** en los equipos y en el servidor.

El objetivo de seguridad es demostrar que cada persona accede con una identidad propia, con los permisos mínimos de su nivel, y que cada intento exitoso o fallido deja evidencia.

---

## 2. Topología y Direccionamiento

> La red de gestión es **privada** y sale de `10.7.30.0/24` (matrícula 0730). No se usa la primera IP utilizable de la red.

### 2.1 Diagrama de Topología

```
                  ┌──────────────┐
                  │   R-AAA      │
                  │   Router     │
                  │ Et0/0        │
                  │ 10.7.30.2/27 │
                  └──────┬───────┘
                         │
                         │ e0/0 (VLAN 10)
                  ┌──────┴───────┐
                  │   SW-AAA     │
                  │   Switch     │
                  │ Vlan10       │
                  │ 10.7.30.3/27 │
                  └──────┬───────┘
                         │ e0/1 (VLAN 10)
                  ┌──────┴───────────────┐
                  │   AAA-SRV            │
                  │   Windows Server 2022│
                  │   AD DS + NPS        │
                  │   10.7.30.4/27       │
                  └──────────────────────┘

   Consola / Auxiliar de R-AAA y SW-AAA ──► RADIUS (UDP 1812/1813) ──► AAA-SRV
   SSH (TCP 22) hacia R-AAA y SW-AAA ──► usuario local (solo desde AAA-SRV)
```

### 2.2 Tabla de Dispositivos

| Dispositivo | Sistema | Interfaz | IP | Máscara | Rol |
|---|---|---|---|---|---|
| **R-AAA** | Cisco IOS 15.4 (IOL) | Et0/0 | 10.7.30.2 | /27 | Router, cliente RADIUS |
| **SW-AAA** | Cisco IOS 15.4 (IOL L2) | Vlan10 | 10.7.30.3 | /27 | Switch, cliente RADIUS |
| **AAA-SRV** | Windows Server 2022 | Ethernet0 | 10.7.30.4 | /27 | Active Directory, NPS (RADIUS) |

| Red | VLAN | Dirección | Hosts utilizables | Broadcast |
|---|---|---|---|---|
| Gestión | 10 | 10.7.30.0/27 | .1 – .30 (se usan .2, .3 y .4) | .31 |

### 2.3 Tabla de Switch

| Interfaz | Modo | VLAN | Conectado a |
|---|---|---|---|
| **e0/0** | Access | 10 | R-AAA `Et0/0` |
| **e0/1** | Access | 10 | AAA-SRV |
| **e0/2 – e0/3, e1/0 – e1/3** | Apagados | 999 | Sin uso |

### 2.4 Active Directory

| Elemento | Valor |
|---|---|
| Dominio | `itla.local` (NetBIOS `ITLA`) |
| Unidad organizativa | `Niveles-AAA` |
| Grupo nivel 0 | `Nivel0` |
| Grupo nivel 5 | `Nivel5` |
| Grupo nivel 10 | `Nivel10` |

| Usuario de AD | Grupo | Nivel de privilegio en el equipo |
|---|---|---|
| `user-n0` | `Nivel0` | 0 |
| `user-n5` | `Nivel5` | 5 |
| `user-n10` | `Nivel10` | 10 |

---

## 3. Diseño de seguridad AAA

### 3.1 Alcance: AAA solo en consola y auxiliar

El enunciado pide que **solo la consola y el puerto auxiliar** usen autenticación y autorización AAA. Se implementa así:

| Línea | Autenticación | Autorización | Contabilidad |
|---|---|---|---|
| `console 0` | RADIUS (NPS), con respaldo local | RADIUS (nivel de privilegio), con respaldo local | RADIUS |
| `aux 0` | RADIUS (NPS), con respaldo local | RADIUS (nivel de privilegio), con respaldo local | RADIUS |
| `vty 0 4` (SSH) | **Solo usuario local** | Local | — |

* **RADIUS no se usa en las líneas VTY.** El SSH se autentica únicamente con el usuario local, y solo se admite desde el servidor de gestión (`10.7.30.4`).
* La lista de métodos `default` es **solo local**: si una línea no tiene lista asignada, nunca queda sin autenticación ni usa RADIUS.
* El servidor RADIUS solo aparece en las listas de consola y auxiliar.

### 3.2 Niveles de autenticación y autorización cubiertos

| Función AAA | Comando | Cobertura |
|---|---|---|
| Autenticación de inicio de sesión | `aaa authentication login` | Consola y auxiliar → RADIUS → local · VTY → local · `default` → local |
| Autenticación de privilegio (`enable`) | `aaa authentication enable default enable` | `enable secret` propio para los niveles **5, 10 y 15** |
| Autorización de exec | `aaa authorization exec` | Consola y auxiliar → RADIUS (devuelve el nivel) → local · VTY → local |
| Autorización en consola | `aaa authorization console` | Aplica la autorización también a la consola |
| Contabilidad | `aaa accounting exec / system / connection` | A RADIUS (NPS) |
| Límite de intentos | `aaa authentication attempts login 3`, `aaa local authentication attempts max-fail 3` | Bloqueo tras 3 fallos |
| Anti fuerza bruta | `login block-for 120 attempts 3 within 60` | VTY, con excepción para el servidor de gestión |

> **Autorización de comandos por nivel:** RADIUS no autoriza comando por comando en Cisco IOS (eso es propio de TACACS+). Por eso el servidor RADIUS **asigna el nivel de privilegio** (`shell:priv-lvl=N`) y los equipos **limitan los comandos de cada nivel** con `privilege exec level`, de modo que cada nivel solo ejecuta lo que le corresponde.

### 3.3 Qué puede hacer cada nivel

| Nivel | Grupo de AD | Comandos permitidos |
|---|---|---|
| **0** | `Nivel0` | Solo los comandos del nivel 0: `disable`, `enable`, `exit`, `help`, `logout` |
| **5** | `Nivel5` | Consulta básica: `show version`, `show ip interface brief`, `ping`, `traceroute`, más `show logging` y `show ip route` |
| **10** | `Nivel10` | Todo el nivel 5, más `show running-config`, `show startup-config`, `show aaa servers`, `show radius statistics` y `configure terminal` con **solo** el modo `interface` (`description`, `shutdown`, `no shutdown`) |
| **15** | Usuario local | Administración completa (solo por SSH o como respaldo) |

### 3.4 Registros (logs)

| Origen | Qué registra | Cómo |
|---|---|---|
| Router y Switch | Inicios de sesión exitosos y fallidos | `login on-success log`, `login on-failure log`, `security authentication failure rate 3 log` |
| Router y Switch | Eventos SSH | `ip ssh logging events` |
| Router y Switch | Eventos de autenticación, autorización y RADIUS en vivo | `debug aaa authentication`, `debug aaa authorization`, `debug radius` |
| Router y Switch | Almacenamiento | `logging buffered 64000 informational` con marca de tiempo y zona horaria |
| NPS | Autenticaciones aceptadas (evento 6272) y rechazadas (evento 6273) | Registro de eventos de NPS y auditoría de la categoría *Network Policy Server* |
| NPS | Contabilidad: inicio y fin de sesión, autenticaciones | Archivo de registro en `C:\NPS-Logs` |

---

## 4. Procedimiento paso a paso

Los pasos están en el orden en que se ejecutan. AAA se activa **al final** de cada equipo y **después** de probar RADIUS, para no perder el acceso.

> ⚠️ **Antes de activar AAA en un equipo:** mantener abierta una sesión de consola y **no guardar** (`write memory`) hasta haber probado el acceso con el usuario local y con un usuario de AD.

> Los nombres de interfaz (`Ethernet0/0`, …) deben ajustarse a los que muestre `show ip interface brief` en la imagen usada en PNETLab. Los nombres de adaptador de Windows (`Ethernet0`) se consultan con `Get-NetAdapter`.

---

### Paso 1. Red virtual y PNETLab

**1.1 — Red virtual del servidor**

La VM del servidor se conecta a una red virtual **Host-only** de VMware (por ejemplo `VMnet15`), **sin DHCP de VMware**, y esa red se enlaza a PNETLab con un nodo **Cloud**. El servidor entra al switch por **un solo cable**.

| VM | Sistema | RAM | vCPU | Red virtual |
|---|---|---|---|---|
| AAA-SRV | Windows Server 2022 | 4 GB | 2 | VMnet15 (Host-only, sin DHCP) |

**1.2 — En PNETLab**

1. Agregar un nodo **Router** (IOL L3) llamado `R-AAA` y un nodo **Switch** (IOL L2) llamado `SW-AAA`.
2. Agregar un nodo `Network` de tipo `Cloud` enlazado a `VMnet15`, llamado `Nube-SRV`.
3. Conectar `Et0/0` de `R-AAA` a `e0/0` de `SW-AAA`.
4. Conectar `Nube-SRV` a `e0/1` de `SW-AAA`.

> Ver evidencia: [01_topologia_pnet.png](screenshots/01_topologia_pnet.png)

---

### Paso 2. Servidor: red, Active Directory, grupos y usuarios

En PowerShell como administrador, un bloque a la vez (script: [`scripts/servidor-ad.ps1`](scripts/servidor-ad.ps1)).

**2.1 — Red y nombre**

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 10.7.30.4 -PrefixLength 27 -DefaultGateway 10.7.30.2
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 10.7.30.4
Rename-Computer -NewName "AAA-SRV" -Restart
```

**2.2 — Active Directory**

```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName "itla.local" -DomainNetbiosName "ITLA" -InstallDns -SafeModeAdministratorPassword (ConvertTo-SecureString "Dsrm-Lab-2026!" -AsPlainText -Force) -Force
```

El servidor se reinicia al terminar. Iniciar sesión con `ITLA\Administrator`.

**2.3 — Unidad organizativa y grupos de nivel 0, 5 y 10**

```powershell
New-ADOrganizationalUnit -Name "Niveles-AAA" -Path "DC=itla,DC=local"

foreach ($n in 0,5,10) {
    New-ADGroup -Name "Nivel$n" -GroupScope Global -GroupCategory Security -Path "OU=Niveles-AAA,DC=itla,DC=local" -Description "Administradores de red con privilegio $n"
}
```

**2.4 — Usuarios, uno por nivel**

```powershell
$pw = ConvertTo-SecureString "Lab12345!" -AsPlainText -Force

foreach ($n in 0,5,10) {
    New-ADUser -Name "user-n$n" -SamAccountName "user-n$n" -UserPrincipalName "user-n$n@itla.local" -Path "OU=Niveles-AAA,DC=itla,DC=local" -AccountPassword $pw -Enabled $true -PasswordNeverExpires $true
    Add-ADGroupMember -Identity "Nivel$n" -Members "user-n$n"
}
```

**Verificación:**

```powershell
Get-ADGroup -Filter 'Name -like "Nivel*"' | Select-Object Name
foreach ($n in 0,5,10) { "Nivel$n :"; Get-ADGroupMember "Nivel$n" | Select-Object -ExpandProperty SamAccountName }
```

> Ver evidencia: [02_servidor_red.png](screenshots/02_servidor_red.png), [03_ad_grupos_usuarios.png](screenshots/03_ad_grupos_usuarios.png)

---

### Paso 3. Servidor: NPS (RADIUS)

**3.1 — Instalar y registrar NPS en Active Directory**

```powershell
Install-WindowsFeature NPAS -IncludeManagementTools
netsh nps add registeredserver
```

**3.2 — Clientes RADIUS (Router y Switch)**

Cada equipo tiene su propio secreto compartido.

```powershell
New-NpsRadiusClient -Name "R-AAA"  -Address "10.7.30.2" -SharedSecret "R4dius-Rtr-2026!"
New-NpsRadiusClient -Name "SW-AAA" -Address "10.7.30.3" -SharedSecret "R4dius-Sw-2026!"
```

**3.3 — Firewall: RADIUS solo desde el Router y el Switch**

Se deshabilitan las reglas predeterminadas de RADIUS (abiertas a cualquier origen) y se crea una que solo admite a los dos equipos.

```powershell
Get-NetFirewallPortFilter -Protocol UDP | Where-Object { $_.LocalPort -in "1812","1813","1645","1646" } | Get-NetFirewallRule | Disable-NetFirewallRule

New-NetFirewallRule -DisplayName "RADIUS-Gestion" -Direction Inbound -Protocol UDP -LocalPort 1812,1813 -RemoteAddress 10.7.30.2,10.7.30.3 -Action Allow
```

**3.4 — Políticas de red (GUI)**

**Ruta:** `Administrador del servidor → Herramientas → Servidor de directivas de redes → NPS (local) → Directivas → Directivas de red → clic derecho → Nueva`

Se crean **tres políticas**, una por grupo. Todas se configuran igual, salvo el grupo y el nivel. Entre paréntesis se indica el nombre en inglés.

| Campo | `Cisco-Nivel10` | `Cisco-Nivel5` | `Cisco-Nivel0` |
|---|---|---|---|
| Nombre de la directiva (Policy name) | `Cisco-Nivel10` | `Cisco-Nivel5` | `Cisco-Nivel0` |
| Tipo de servidor de acceso a la red (Type of network access server) | `Sin especificar` | `Sin especificar` | `Sin especificar` |
| Condición 1: **Grupos de Windows** (Windows Groups) | `ITLA\Nivel10` | `ITLA\Nivel5` | `ITLA\Nivel0` |
| Condición 2: **Nombre descriptivo del cliente** (Client Friendly Name) | `^(R-AAA\|SW-AAA)$` | `^(R-AAA\|SW-AAA)$` | `^(R-AAA\|SW-AAA)$` |
| Permiso de acceso (Access permission) | `Acceso concedido` | `Acceso concedido` | `Acceso concedido` |
| Métodos de autenticación (Authentication methods) | Solo **Autenticación sin cifrar (PAP, SPAP)** | igual | igual |
| Atributo estándar **Service-Type** | `Login` | `Login` | `Login` |
| Atributo específico del proveedor **Cisco-AV-Pair** | `shell:priv-lvl=10` | `shell:priv-lvl=5` | `shell:priv-lvl=0` |

Pasos del asistente *Nueva directiva de red* (para cada política):

1. **Especificar el nombre de la directiva de red y el tipo de conexión:** escribir el nombre de la directiva y dejar *Tipo de servidor de acceso a la red* en `Sin especificar`. Pulsar **Siguiente**.
2. **Especificar condiciones:** pulsar **Agregar...** para cada condición.
   * **Condición 1:** en la ventana *Seleccionar condición*, dentro del grupo **Grupos**, elegir **Grupos de Windows** → **Agregar...** → **Agregar grupos...** → escribir el grupo del nivel (por ejemplo `Nivel10`) → **Comprobar nombres** → **Aceptar**.
   * **Condición 2:** pulsar **Agregar...** de nuevo, **desplazarse hacia abajo** en la ventana *Seleccionar condición* hasta el grupo **Cliente RADIUS** (RADIUS Client) y elegir **Nombre descriptivo del cliente** → **Agregar...** → escribir `^(R-AAA|SW-AAA)$` → **Aceptar**.

   > La *Condición 2* no está en la lista inicial: se encuentra dentro del grupo **Cliente RADIUS**, más abajo en la misma ventana. Limita la política a los dos equipos. Aunque no se agregue, solo pueden autenticar los clientes registrados en **Clientes RADIUS** (Paso 3.2).

   Pulsar **Siguiente**.
3. **Especificar permiso de acceso:** marcar **Acceso concedido**. Pulsar **Siguiente**.
4. **Configurar métodos de autenticación:** quitar todos los métodos marcados (EAP, MS-CHAP y MS-CHAP v2) y marcar **solo** **Autenticación sin cifrar (PAP, SPAP)**. Dejar desmarcada la opción *Permitir que los clientes se conecten sin negociar un método de autenticación*. Si aparece un aviso sobre la autenticación sin cifrar, aceptarlo: Cisco IOS envía la contraseña con PAP y el secreto compartido la protege entre el equipo y NPS. Pulsar **Siguiente**.
5. **Configurar restricciones:** sin cambios. Pulsar **Siguiente**.
6. **Configurar valores:**
   * **Atributos RADIUS → Estándar:** seleccionar `Framed-Protocol` y `Service-Type` (con valor `Framed`) y pulsar **Quitar**. Pulsar **Agregar...** → **Service-Type** → **Agregar...** → valor `Login` → **Aceptar**.
   * **Atributos RADIUS → Específico del proveedor:** pulsar **Agregar...** → *Proveedor*: `Cisco` → **Agregar...** → atributo **Cisco-AV-Pair** → **Agregar...** → valor `shell:priv-lvl=<nivel>` (por ejemplo `shell:priv-lvl=10`) → **Aceptar**.

   Pulsar **Siguiente**.
7. **Completar la nueva directiva de red:** revisar el resumen y pulsar **Finalizar**.

Al terminar, verificar el **orden de procesamiento** en `Directivas de red`: las tres políticas `Cisco-*` deben estar **por encima** de las dos políticas predeterminadas (*Conexiones al servidor de Enrutamiento y acceso remoto de Microsoft* y *Conexiones a otros servidores de acceso*). Si no es así: clic derecho sobre la política → **Subir**.

**3.5 — Registros de NPS**

**Registro de eventos (autenticaciones aceptadas y rechazadas):**
`NPS (local) → clic derecho → Propiedades → pestaña General` → marcar **Solicitudes de autenticación rechazadas** y **Solicitudes de autenticación correctas** (*Rejected / Successful authentication requests*).

**Auditoría de la categoría *Servidor de directivas de redes*:**

```powershell
auditpol /set /subcategory:"{0CCE9243-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable
```

**Registro de contabilidad en archivo:**

```powershell
New-Item -ItemType Directory -Path C:\NPS-Logs -Force
```

**Ruta:** `NPS (local) → Contabilidad → Configurar contabilidad` y, en el asistente, elegir **Registrar en un archivo de texto en el equipo local**. Después, en `NPS (local) → Contabilidad → Cambiar propiedades del archivo de registro`:

| Pestaña | Campo | Valor |
|---|---|---|
| Configuración | Registrar la siguiente información | Solicitudes de contabilidad, Solicitudes de autenticación, Estado de contabilidad periódico, Estado de autenticación periódico |
| Archivo de registro | Directorio | `C:\NPS-Logs` |
| Archivo de registro | Formato | `IAS` |

> Ver evidencia: [04_nps_clientes_radius.png](screenshots/04_nps_clientes_radius.png), [05_nps_politicas.png](screenshots/05_nps_politicas.png), [06_nps_politica_atributos.png](screenshots/06_nps_politica_atributos.png), [07_nps_accounting_eventos.png](screenshots/07_nps_accounting_eventos.png)

---

### Paso 4. Switch: red base y VLAN de gestión

Consola de `SW-AAA` (script: [`scripts/sw-aaa-base.txt`](scripts/sw-aaa-base.txt)):

```bash
enable
configure terminal

hostname SW-AAA
no ip domain-lookup
ip domain-name itla.local
spanning-tree mode rapid-pvst
clock timezone AST -4 0

vlan 10
 name GESTION
vlan 999
 name BLACKHOLE
exit

interface Vlan10
 description Gestion
 ip address 10.7.30.3 255.255.255.224
 no shutdown
exit

ip default-gateway 10.7.30.2

interface range Ethernet0/0 - 1
 switchport mode access
 switchport access vlan 10
 switchport nonegotiate
 spanning-tree portfast
 no shutdown
exit

interface Ethernet0/0
 description Enlace hacia R-AAA
exit

interface Ethernet0/1
 description AAA-SRV
exit

interface range Ethernet0/2 - 3 , Ethernet1/0 - 3
 description Puerto sin uso
 switchport mode access
 switchport access vlan 999
 shutdown
exit

end
```

> Ver evidencia: [08_switch_base.png](screenshots/08_switch_base.png)

---

### Paso 5. Router: red base

Consola de `R-AAA` (script: [`scripts/r-aaa-base.txt`](scripts/r-aaa-base.txt)):

```bash
enable
configure terminal

hostname R-AAA
no ip domain-lookup
ip domain-name itla.local
clock timezone AST -4 0

interface Ethernet0/0
 description Gestion - hacia SW-AAA
 ip address 10.7.30.2 255.255.255.224
 no shutdown
exit

interface range Ethernet0/1 - 3
 description Puerto sin uso
 shutdown
exit

end
```

> Ver evidencia: [09_router_base.png](screenshots/09_router_base.png)

---

### Paso 6. Verificar la conectividad

**Desde el Router:**

```bash
ping 10.7.30.3
ping 10.7.30.4
```

**Desde el Switch:**

```bash
ping 10.7.30.2
ping 10.7.30.4
```

**Desde el Servidor (PowerShell):**

```powershell
ping 10.7.30.2
ping 10.7.30.3
```

Los pings deben responder. Si el ping hacia el servidor falla, revisar que el firewall de Windows permita el ICMP de entrada.

> Ver evidencia: [10_ping_conectividad.png](screenshots/10_ping_conectividad.png)

---

### Paso 7. Router: usuario local, SSH y niveles de privilegio

Consola de `R-AAA`, un bloque a la vez (script: [`scripts/r-aaa-seguridad.txt`](scripts/r-aaa-seguridad.txt)).

**7.1 — Endurecimiento, contraseñas por nivel y usuario local**

```bash
configure terminal

service password-encryption
no service pad
no ip http server
no ip http secure-server
no ip source-route
security passwords min-length 10

enable secret level 5 Nivel5-Enable#2026
enable secret level 10 Nivel10-Enable#2026
enable secret Nivel15-Enable#2026

username admin-local privilege 15 secret Admin-Local#2026

banner login ^C
ACCESO RESTRINGIDO: solo personal autorizado. Toda actividad es registrada.
^C

end
```

**7.2 — SSH versión 2, solo desde el servidor de gestión**

```bash
configure terminal

crypto key generate rsa modulus 2048
ip ssh version 2
ip ssh time-out 60
ip ssh authentication-retries 3
ip ssh logging events

ip access-list standard SSH-MGMT
 permit host 10.7.30.4
 deny any log
exit

login block-for 120 attempts 3 within 60
login quiet-mode access-class SSH-MGMT

end
```

**7.3 — Comandos permitidos por nivel de privilegio**

```bash
configure terminal

! Nivel 5: consulta básica
privilege exec level 5 show
privilege exec level 5 show logging
privilege exec level 5 show ip route

! Nivel 10: consulta ampliada
privilege exec level 10 show running-config
privilege exec level 10 show startup-config
privilege exec level 10 show aaa servers
privilege exec level 10 show radius statistics

! Nivel 10: configuración limitada al modo interface
privilege exec level 10 configure terminal
privilege exec level 10 configure
privilege configure level 10 interface
privilege configure level 10 end
privilege interface all level 10 description
privilege interface all level 10 shutdown
privilege interface level 10 end

end
```

> Ver evidencia: [11_router_usuario_ssh.png](screenshots/11_router_usuario_ssh.png)

---

### Paso 8. Router: RADIUS, AAA y logs

Consola de `R-AAA`, un bloque a la vez. **Mantener abierta la sesión de consola** hasta terminar las pruebas del Paso 12.

**8.1 — Cliente RADIUS (NPS) y grupo de servidores**

```bash
configure terminal

aaa new-model
aaa authentication login default local

radius server NPS-AAA
 address ipv4 10.7.30.4 auth-port 1812 acct-port 1813
 key R4dius-Rtr-2026!
 timeout 5
 retransmit 2
exit

aaa group server radius NPS-GROUP
 server name NPS-AAA
 ip radius source-interface Ethernet0/0
exit

end
```

**8.2 — Probar RADIUS antes de aplicarlo a las líneas**

```bash
test aaa group NPS-GROUP user-n10 Lab12345! new-code
test aaa group NPS-GROUP user-n5 Lab12345! new-code
test aaa group NPS-GROUP user-n0 Lab12345! new-code
```

Cada uno debe responder `User successfully authenticated`. Si falla, revisar el secreto compartido, el firewall del servidor y que el cliente `R-AAA` exista en NPS (Paso 3).

> Ver evidencia: [12_router_radius_test.png](screenshots/12_router_radius_test.png)

**8.3 — Listas de métodos de AAA**

```bash
configure terminal

aaa authentication login CON-AUX-AAA group NPS-GROUP local
aaa authentication login VTY-LOCAL local
aaa authentication enable default enable
aaa authentication attempts login 3
aaa authentication fail-message ^C
Acceso denegado.
^C
aaa local authentication attempts max-fail 3

aaa authorization console
aaa authorization exec CON-AUX-AAA group NPS-GROUP local
aaa authorization exec VTY-LOCAL local
aaa authorization exec default local

aaa accounting exec CON-AUX-AAA start-stop group NPS-GROUP
aaa accounting system default start-stop group NPS-GROUP
aaa accounting connection default start-stop group NPS-GROUP

end
```

**8.4 — Aplicar AAA a las líneas: RADIUS solo en consola y auxiliar**

```bash
configure terminal

line con 0
 exec-timeout 5 0
 logging synchronous
 privilege level 0
 login authentication CON-AUX-AAA
 authorization exec CON-AUX-AAA
 accounting exec CON-AUX-AAA
exit

line aux 0
 exec-timeout 5 0
 logging synchronous
 privilege level 0
 login authentication CON-AUX-AAA
 authorization exec CON-AUX-AAA
 accounting exec CON-AUX-AAA
 transport input none
exit

line vty 0 4
 exec-timeout 5 0
 logging synchronous
 privilege level 0
 login authentication VTY-LOCAL
 authorization exec VTY-LOCAL
 access-class SSH-MGMT in
 transport input ssh
 transport output none
exit

end
```

**8.5 — Logs de autenticación, autorización y RADIUS**

```bash
configure terminal

service timestamps log datetime msec localtime show-timezone
service timestamps debug datetime msec localtime show-timezone
logging buffered 64000 informational
logging console warnings

login on-success log
login on-failure log
security authentication failure rate 3 log

end
```

Para ver en vivo la autenticación, la autorización y RADIUS (durante las pruebas):

```bash
debug aaa authentication
debug aaa authorization
debug radius
```

Se apagan con `undebug all`.

**Verificación:**

```bash
show aaa servers
show running-config | section aaa
show running-config | section line
```

> Ver evidencia: [13_router_aaa_lineas.png](screenshots/13_router_aaa_lineas.png)

---

### Paso 9. Switch: usuario local, SSH y niveles de privilegio

Consola de `SW-AAA`, un bloque a la vez (script: [`scripts/sw-aaa-seguridad.txt`](scripts/sw-aaa-seguridad.txt)). Es idéntico al del Router.

**9.1 — Endurecimiento, contraseñas por nivel y usuario local**

```bash
configure terminal

service password-encryption
no service pad
no ip http server
no ip http secure-server
no ip source-route
security passwords min-length 10

enable secret level 5 Nivel5-Enable#2026
enable secret level 10 Nivel10-Enable#2026
enable secret Nivel15-Enable#2026

username admin-local privilege 15 secret Admin-Local#2026

banner login ^C
ACCESO RESTRINGIDO: solo personal autorizado. Toda actividad es registrada.
^C

end
```

**9.2 — SSH versión 2, solo desde el servidor de gestión**

```bash
configure terminal

crypto key generate rsa modulus 2048
ip ssh version 2
ip ssh time-out 60
ip ssh authentication-retries 3
ip ssh logging events

ip access-list standard SSH-MGMT
 permit host 10.7.30.4
 deny any log
exit

login block-for 120 attempts 3 within 60
login quiet-mode access-class SSH-MGMT

end
```

**9.3 — Comandos permitidos por nivel de privilegio**

```bash
configure terminal

privilege exec level 5 show
privilege exec level 5 show logging
privilege exec level 5 show ip route

privilege exec level 10 show running-config
privilege exec level 10 show startup-config
privilege exec level 10 show aaa servers
privilege exec level 10 show radius statistics

privilege exec level 10 configure terminal
privilege exec level 10 configure
privilege configure level 10 interface
privilege configure level 10 end
privilege interface all level 10 description
privilege interface all level 10 shutdown
privilege interface level 10 end

end
```

> Ver evidencia: [14_switch_usuario_ssh.png](screenshots/14_switch_usuario_ssh.png)

---

### Paso 10. Switch: RADIUS, AAA y logs

Consola de `SW-AAA`, un bloque a la vez. **Mantener abierta la sesión de consola** hasta terminar las pruebas.

**10.1 — Cliente RADIUS (NPS) y grupo de servidores**

```bash
configure terminal

aaa new-model
aaa authentication login default local

radius server NPS-AAA
 address ipv4 10.7.30.4 auth-port 1812 acct-port 1813
 key R4dius-Sw-2026!
 timeout 5
 retransmit 2
exit

aaa group server radius NPS-GROUP
 server name NPS-AAA
 ip radius source-interface Vlan10
exit

end
```

**10.2 — Probar RADIUS antes de aplicarlo a las líneas**

```bash
test aaa group NPS-GROUP user-n10 Lab12345! new-code
test aaa group NPS-GROUP user-n5 Lab12345! new-code
test aaa group NPS-GROUP user-n0 Lab12345! new-code
```

> Ver evidencia: [15_switch_radius_test.png](screenshots/15_switch_radius_test.png)

**10.3 — Listas de métodos de AAA**

```bash
configure terminal

aaa authentication login CON-AUX-AAA group NPS-GROUP local
aaa authentication login VTY-LOCAL local
aaa authentication enable default enable
aaa authentication attempts login 3
aaa authentication fail-message ^C
Acceso denegado.
^C
aaa local authentication attempts max-fail 3

aaa authorization console
aaa authorization exec CON-AUX-AAA group NPS-GROUP local
aaa authorization exec VTY-LOCAL local
aaa authorization exec default local

aaa accounting exec CON-AUX-AAA start-stop group NPS-GROUP
aaa accounting system default start-stop group NPS-GROUP
aaa accounting connection default start-stop group NPS-GROUP

end
```

**10.4 — Aplicar AAA a las líneas: RADIUS solo en consola y auxiliar**

```bash
configure terminal

line con 0
 exec-timeout 5 0
 logging synchronous
 privilege level 0
 login authentication CON-AUX-AAA
 authorization exec CON-AUX-AAA
 accounting exec CON-AUX-AAA
exit

line aux 0
 exec-timeout 5 0
 logging synchronous
 privilege level 0
 login authentication CON-AUX-AAA
 authorization exec CON-AUX-AAA
 accounting exec CON-AUX-AAA
 transport input none
exit

line vty 0 4
 exec-timeout 5 0
 logging synchronous
 privilege level 0
 login authentication VTY-LOCAL
 authorization exec VTY-LOCAL
 access-class SSH-MGMT in
 transport input ssh
 transport output none
exit

end
```

**10.5 — Logs de autenticación, autorización y RADIUS**

```bash
configure terminal

service timestamps log datetime msec localtime show-timezone
service timestamps debug datetime msec localtime show-timezone
logging buffered 64000 informational
logging console warnings

login on-success log
login on-failure log
security authentication failure rate 3 log

end
```

Para ver en vivo la autenticación, la autorización y RADIUS: `debug aaa authentication`, `debug aaa authorization` y `debug radius` (se apagan con `undebug all`).

**Verificación:**

```bash
show aaa servers
show running-config | section aaa
show running-config | section line
```

> Ver evidencia: [16_switch_aaa_lineas.png](screenshots/16_switch_aaa_lineas.png)

---

### Paso 11. Guardar y exportar las configuraciones

Con todas las pruebas del Paso 12 aprobadas:

**Router y Switch:**

```bash
write memory
terminal length 0
show running-config
```

Copiar la salida de `show running-config` de cada equipo a `running-configs/r-aaa-running-config.txt` y `running-configs/sw-aaa-running-config.txt`.

**Servidor (configuración de NPS, sin los secretos compartidos):**

```powershell
New-Item -ItemType Directory -Path C:\NPS -Force
netsh nps export filename="C:\NPS\nps-config.xml" exportPSK=NO
```

Copiar `nps-config.xml` a `running-configs/nps-config.xml`.

> Ver evidencia: [17_nps_export.png](screenshots/17_nps_export.png)

---

### Paso 12. Pruebas de verificación

**12.1 — Consola del Router con cada nivel (RADIUS + AD)**

Con `debug aaa authentication`, `debug aaa authorization` y `debug radius` activos, abrir la consola de `R-AAA` e iniciar sesión con cada usuario (contraseña `Lab12345!`):

| Usuario | Prompt esperado | Prueba | Resultado esperado |
|---|---|---|---|
| `user-n0` | `R-AAA>` | `show version` | ❌ `% Invalid input` |
| `user-n5` | `R-AAA#` | `show ip interface brief` y `show logging` | ✅ Se muestran |
| `user-n5` | `R-AAA#` | `show running-config` y `configure terminal` | ❌ `% Invalid input` |
| `user-n10` | `R-AAA#` | `show running-config` | ✅ Se muestra |
| `user-n10` | `R-AAA#` | `configure terminal` → `interface Ethernet0/3` → `description prueba` → `shutdown` | ✅ Se aceptan |
| `user-n10` | `R-AAA(config)#` | `hostname PRUEBA` o `username x secret y` | ❌ `% Invalid input` |

En cada inicio de sesión se verifica el nivel con `show privilege` (debe mostrar `Current privilege level is 0`, `5` o `10`).

> Ver evidencia: [18_consola_nivel0.png](screenshots/18_consola_nivel0.png), [19_consola_nivel5.png](screenshots/19_consola_nivel5.png), [20_consola_nivel10.png](screenshots/20_consola_nivel10.png)

**12.2 — Contraseña incorrecta y respaldo local**

* Iniciar sesión por consola con `user-n10` y una **contraseña incorrecta**: debe rechazar el acceso y generar `%SEC_LOGIN-4-LOGIN_FAILED`.
* En el servidor, detener NPS y comprobar el **respaldo local**:

```powershell
Stop-Service IAS
```

En la consola, iniciar sesión con `admin-local` (`Admin-Local#2026`): tras agotar el tiempo de espera de RADIUS, el acceso se concede por la base local con nivel 15. Reiniciar el servicio:

```powershell
Start-Service IAS
```

> Ver evidencia: [21_consola_fallo_password.png](screenshots/21_consola_fallo_password.png), [22_consola_fallback_local.png](screenshots/22_consola_fallback_local.png)

**12.3 — Puerto auxiliar**

El puerto auxiliar usa las mismas listas de métodos que la consola. En IOL no se puede abrir una sesión física por el auxiliar, así que se comprueba con:

```bash
show line
show running-config | section line aux
```

Debe mostrar `line aux 0` con `login authentication CON-AUX-AAA`, `authorization exec CON-AUX-AAA` y `accounting exec CON-AUX-AAA`.

> Ver evidencia: [23_show_line_aux.png](screenshots/23_show_line_aux.png)

**12.4 — SSH (solo usuario local) y Telnet deshabilitado**

Desde el servidor (PowerShell):

```powershell
ssh -c aes256-cbc admin-local@10.7.30.2        # debe entrar con nivel 15
ssh -c aes256-cbc user-n10@10.7.30.2           # debe ser DENEGADO (RADIUS no se usa en VTY)
Test-NetConnection 10.7.30.2 -Port 23   # Telnet: debe fallar
```

En el Router, después del acceso por SSH:

```bash
show ip ssh
show ssh
show privilege
```

`show ip ssh` debe indicar `SSH Enabled - version 2.0`. Desde otro origen distinto de `10.7.30.4`, el acceso SSH se rechaza por la lista `SSH-MGMT`.

> Ver evidencia: [24_ssh_local_ok.png](screenshots/24_ssh_local_ok.png), [25_ssh_radius_denegado.png](screenshots/25_ssh_radius_denegado.png), [26_telnet_rechazado.png](screenshots/26_telnet_rechazado.png)

**12.5 — Logs en el Router**

```bash
show logging
show aaa servers
show radius statistics
```

En `show logging` deben verse `%SEC_LOGIN-5-LOGIN_SUCCESS`, `%SEC_LOGIN-4-LOGIN_FAILED` y los eventos de SSH. Durante un inicio de sesión por consola, la salida de `debug aaa authentication`, `debug aaa authorization` y `debug radius` muestra `Access-Request`, `Access-Accept` y el atributo `shell:priv-lvl=N`.

> Ver evidencia: [27_logs_router.png](screenshots/27_logs_router.png), [28_debug_radius.png](screenshots/28_debug_radius.png)

**12.6 — Logs en el servidor (NPS)**

* **Visor de eventos:** `Administrador del servidor → Herramientas → Visor de eventos → Registros de Windows → Seguridad`, filtrar por los eventos **6272** (*El servidor de directivas de redes concedió acceso a un usuario*) y **6273** (*...denegó el acceso a un usuario*) de los intentos anteriores. Cada evento muestra el usuario, el cliente RADIUS (`R-AAA` o `SW-AAA`) y la política que aplicó (`Cisco-Nivel10`, etc.).
* **Contabilidad:** abrir el archivo de registro de `C:\NPS-Logs`:

```powershell
Get-ChildItem C:\NPS-Logs | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content -Tail 30
```

Deben aparecer los registros de inicio y fin de sesión (`Acct-Status-Type`) de cada acceso por consola.

> Ver evidencia: [29_nps_eventos.png](screenshots/29_nps_eventos.png), [30_nps_accounting_log.png](screenshots/30_nps_accounting_log.png)

**12.7 — Pruebas en el Switch**

Se replicó la matriz de pruebas en el Switch `SW-AAA` (10.7.30.3), confirmando el mismo comportamiento que en el Router `R-AAA`:.

- Consola: Autenticación centralizada mediante RADIUS (NPS) con asignación dinámica de privilegios por Active Directory (`user-n0` restringido, `user-n5` consulta básica, `user-n10` gestión de interfaces).

- VTY (SSH): Autenticación restringida exclusivamente al usuario local (`admin-local`) desde la IP de gestión `10.7.30.4`, denegando usuarios de AD y bloqueando Telnet.

- Registros: Generación de eventos de auditoría local (`show logging`) y envío de contabilidad al servidor NPS.

> Ver evidencia: [31_switch_pruebas.png](screenshots/31_switch_pruebas.png)

---

## 5. Matriz de cumplimiento de requisitos

| Requisito del enunciado | Cómo se cumple | Paso |
|---|---|---|
| **Repositorio de GitHub** | Este repositorio | — |
| Documentación profesional en el repositorio | Este `README.md` y la carpeta `screenshots/` | — |
| Video demostrativo al principio del repositorio | Enlace al inicio de este documento | Inicio |
| Documentación con imágenes | Capturas numeradas en `screenshots/` | 6 |
| Documentación con diagramas | Diagrama de topología | 2.1 |
| Propósito del laboratorio | Sección 1 | 1 |
| Todo script utilizado en el repositorio | Carpeta `scripts/` | 7 |
| Running-configs en el repositorio | Carpeta `running-configs/` | 11 |
| **Router:** seguridad en todos los niveles de autenticación y autorización | `aaa authentication login/enable`, `aaa authorization console/exec`, contraseñas `enable secret` por nivel, comandos por nivel de privilegio | 3.2, 7, 8 |
| **Router:** RADIUS como cliente | `radius server NPS-AAA` y `aaa group server radius NPS-GROUP` | 8.1, 8.2 |
| **Router:** usuario local | `username admin-local privilege 15` | 7.1 |
| **Router:** AAA solo en consola y auxiliar | Listas `CON-AUX-AAA` aplicadas solo a `line con 0` y `line aux 0`; VTY con lista local | 3.1, 8.4 |
| **Router:** logs de autenticación, autorización y RADIUS | `login on-success/on-failure log`, `logging buffered`, `debug aaa`, `debug radius`, contabilidad RADIUS | 3.4, 8.5, 12.5 |
| **Router:** servicio SSH | SSH versión 2, claves RSA de 2048 bits, solo desde el servidor de gestión | 7.2, 12.4 |
| **Switch:** seguridad en todos los niveles de autenticación y autorización | Igual que el Router | 3.2, 9, 10 |
| **Switch:** RADIUS como cliente | `radius server NPS-AAA` y `aaa group server radius NPS-GROUP` | 10.1, 10.2 |
| **Switch:** usuario local | `username admin-local privilege 15` | 9.1 |
| **Switch:** AAA solo en consola y auxiliar | Igual que el Router | 3.1, 10.4 |
| **Switch:** logs de autenticación, autorización y RADIUS | Igual que el Router | 3.4, 10.5, 12.7 |
| **Switch:** servicio SSH | SSH versión 2, solo desde el servidor de gestión | 9.2, 12.7 |
| **Servidor:** Active Directory con 1 grupo nivel 0 | Grupo `Nivel0` | 2.3 |
| **Servidor:** 1 grupo nivel 5 | Grupo `Nivel5` | 2.3 |
| **Servidor:** 1 grupo nivel 10 | Grupo `Nivel10` | 2.3 |
| **Servidor:** servicio NPS | Rol Servicios de acceso y directivas de redes (NPAS), tres políticas por grupo | 3 |
| **Entregable:** archivo TXT con el enlace del repositorio | `entregable/ArleneFernandez_20250730_P8.txt` | 7 |

---

## 6. Capturas de Pantalla

Numeradas en el orden en que se toman durante el procedimiento.

| # | Archivo | Paso | Descripción |
|---|---|---|---|
| 01 | [`01_topologia_pnet.png`](screenshots/01_topologia_pnet.png) | 1 | Topología en PNETLab: R-AAA, SW-AAA y la nube del servidor. |
| 02 | [`02_servidor_red.png`](screenshots/02_servidor_red.png) | 2.1 | `ipconfig` del servidor con `10.7.30.4/27`. |
| 03 | [`03_ad_grupos_usuarios.png`](screenshots/03_ad_grupos_usuarios.png) | 2.3–2.4 | Grupos `Nivel0`, `Nivel5`, `Nivel10` y sus usuarios. |
| 04 | [`04_nps_clientes_radius.png`](screenshots/04_nps_clientes_radius.png) | 3.2 | Clientes RADIUS `R-AAA` y `SW-AAA` en NPS. |
| 05 | [`05_nps_politicas.png`](screenshots/05_nps_politicas.png) | 3.4 | Las tres políticas de red `Cisco-*` en su orden. |
| 06 | [`06_nps_politica_atributos.png`](screenshots/06_nps_politica_atributos.png) | 3.4 | Atributos de una política: `Service-Type` y `Cisco-AV-Pair`. |
| 07 | [`07_nps_accounting_eventos.png`](screenshots/07_nps_accounting_eventos.png) | 3.5 | Registro de eventos y contabilidad configurados. |
| 08 | [`08_switch_base.png`](screenshots/08_switch_base.png) | 4 | `show vlan brief` e `show ip interface brief` del switch. |
| 09 | [`09_router_base.png`](screenshots/09_router_base.png) | 5 | `show ip interface brief` del router. |
| 10 | [`10_ping_conectividad.png`](screenshots/10_ping_conectividad.png) | 6 | Pings entre los tres equipos. |
| 11 | [`11_router_usuario_ssh.png`](screenshots/11_router_usuario_ssh.png) | 7 | Usuario local, SSH y niveles de privilegio del router. |
| 12 | [`12_router_radius_test.png`](screenshots/12_router_radius_test.png) | 8.2 | `test aaa` exitoso con los tres usuarios, en el router. |
| 13 | [`13_router_aaa_lineas.png`](screenshots/13_router_aaa_lineas.png) | 8.5 | `show running-config` del router: secciones `aaa` y `line`. |
| 14 | [`14_switch_usuario_ssh.png`](screenshots/14_switch_usuario_ssh.png) | 9 | Usuario local, SSH y niveles de privilegio del switch. |
| 15 | [`15_switch_radius_test.png`](screenshots/15_switch_radius_test.png) | 10.2 | `test aaa` exitoso con los tres usuarios, en el switch. |
| 16 | [`16_switch_aaa_lineas.png`](screenshots/16_switch_aaa_lineas.png) | 10.5 | `show running-config` del switch: secciones `aaa` y `line`. |
| 17 | [`17_nps_export.png`](screenshots/17_nps_export.png) | 11 | Exportación de la configuración de NPS. |
| 18 | [`18_consola_nivel0.png`](screenshots/18_consola_nivel0.png) | 12.1 | Consola con `user-n0`: comandos bloqueados. |
| 19 | [`19_consola_nivel5.png`](screenshots/19_consola_nivel5.png) | 12.1 | Consola con `user-n5`: consulta permitida, configuración bloqueada. |
| 20 | [`20_consola_nivel10.png`](screenshots/20_consola_nivel10.png) | 12.1 | Consola con `user-n10`: configuración de interfaz permitida, resto bloqueado. |
| 21 | [`21_consola_fallo_password.png`](screenshots/21_consola_fallo_password.png) | 12.2 | Acceso rechazado con contraseña incorrecta. |
| 22 | [`22_consola_fallback_local.png`](screenshots/22_consola_fallback_local.png) | 12.2 | Acceso con el usuario local cuando NPS está detenido. |
| 23 | [`23_show_line_aux.png`](screenshots/23_show_line_aux.png) | 12.3 | Línea auxiliar con las listas AAA. |
| 24 | [`24_ssh_local_ok.png`](screenshots/24_ssh_local_ok.png) | 12.4 | SSH exitoso con el usuario local. |
| 25 | [`25_ssh_radius_denegado.png`](screenshots/25_ssh_radius_denegado.png) | 12.4 | SSH con un usuario de AD denegado. |
| 26 | [`26_telnet_rechazado.png`](screenshots/26_telnet_rechazado.png) | 12.4 | Telnet rechazado. |
| 27 | [`27_logs_router.png`](screenshots/27_logs_router.png) | 12.5 | `show logging` con inicios de sesión exitosos y fallidos. |
| 28 | [`28_debug_radius.png`](screenshots/28_debug_radius.png) | 12.5 | `debug aaa` y `debug radius` durante un inicio de sesión. |
| 29 | [`29_nps_eventos.png`](screenshots/29_nps_eventos.png) | 12.6 | Eventos 6272 y 6273 en el Visor de eventos. |
| 30 | [`30_nps_accounting_log.png`](screenshots/30_nps_accounting_log.png) | 12.6 | Archivo de contabilidad de NPS. |
| 31 | [`31_switch_pruebas.png`](screenshots/31_switch_pruebas.png) | 12.7 | Pruebas de consola, SSH y logs en el switch. |

---

## 7. Estructura del Repositorio

```
/
├── README.md                  ← este documento
├── screenshots/               ← capturas numeradas de cada configuración
├── scripts/
│   ├── servidor-ad.ps1        ← servidor: red, Active Directory, grupos, usuarios y NPS
│   ├── sw-aaa-base.txt        ← switch: red base y VLAN de gestión
│   ├── sw-aaa-seguridad.txt   ← switch: usuario local, SSH, niveles, RADIUS, AAA y logs
│   ├── r-aaa-base.txt         ← router: red base
│   └── r-aaa-seguridad.txt    ← router: usuario local, SSH, niveles, RADIUS, AAA y logs
├── running-configs/
│   ├── r-aaa-running-config.txt
│   ├── sw-aaa-running-config.txt
│   └── nps-config.xml
```
