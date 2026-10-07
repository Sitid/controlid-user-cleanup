<#
.SYNOPSIS
    Elimina usuarios de relojes Control iD (iDFace / iDFlex / FACE MAX) a través de su API HTTP,
    con modo verificación, confirmación por nombre y verificación posterior.

.DESCRIPTION
    Pensado para limpiar personal dado de baja que quedó cargado en los relojes cuando el
    sistema que los administra no los borra.

    Entrada: un archivo (TSV por defecto) con una fila por persona y reloj, con estas columnas:
        id_persona, apellido, nombre, id_reloj, dni, reloj, serial
      - id_persona : identificador interno (legajo). Solo se usa para el reporte.
      - id_reloj   : ID con el que el sistema carga a la persona en el reloj (suele ser el legajo).
      - dni        : documento; algunas instalaciones cargan a la persona con el DNI como ID.
      - reloj      : nombre del reloj (se usa para buscar la IP en el mapa).
      - serial     : opcional, número de serie del reloj.

    Mapa de IPs: CSV separado por ';' con columnas  reloj;ip  (y opcionalmente serial).
    Se busca la IP primero por nombre de reloj y después por serial.

    Para cada reloj y persona:
      1. Busca al usuario en el reloj por "id" y por "registration", con id_reloj y con dni.
      2. Lo considera "la misma persona" solo si el nombre del reloj contiene el primer
         apellido. Si hay varias coincidencias, borra todas solo si son exactamente la misma
         persona (mismo nombre completo, o el mismo nombre cortado por el reloj).
      3. Sin -Borrar SOLO INFORMA. Con -Borrar elimina tarjetas, huellas, roles, grupos, foto
         y el usuario, y vuelve a consultar al reloj para confirmar que ya no está.
    Deja un CSV de resultados (se guarda al terminar cada reloj).

.EXAMPLE
    # Verificar, sin borrar nada
    powershell -ExecutionPolicy Bypass -File .\Limpiar-UsuariosControlID.ps1 -Archivo .\usuarios.tsv -MapaIP .\relojes.csv

.EXAMPLE
    # Borrar, salteando dos relojes
    powershell -ExecutionPolicy Bypass -File .\Limpiar-UsuariosControlID.ps1 -Archivo .\usuarios.tsv -MapaIP .\relojes.csv -Excluir "Reloj A,Reloj B" -Borrar

.NOTES
    Requiere Windows PowerShell 5.1 o PowerShell 7+, acceso de red a los relojes y un usuario
    administrador de los equipos. Probar siempre primero sin -Borrar y con un piloto chico.
#>
param(
    [Parameter(Mandatory = $true)][string]$Archivo,
    [Parameter(Mandatory = $true)][string]$MapaIP,
    [switch]$Borrar,
    [switch]$Https,
    [int]$Puerto = 0,
    [int]$TimeoutSeg = 8,
    [string]$Delimitador = "`t",
    [string[]]$Excluir = @()          # nombres de relojes a saltear: -Excluir "Reloj A,Reloj B"
)

$ErrorActionPreference = 'Stop'
# con "powershell -File" la lista llega como un solo texto "A,B": se separa por comas
$Excluir = @($Excluir | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
[System.Net.ServicePointManager]::DefaultConnectionLimit = 20
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }   # los relojes usan certificados autofirmados

$filas = @(Import-Csv -Path $Archivo -Delimiter $Delimitador -Encoding UTF8)
if (-not $filas) { Write-Host "El archivo no tiene filas." -ForegroundColor Red; exit 1 }

$ipPorSerial = @{}; $ipPorNombre = @{}
foreach ($m in (Import-Csv -Path $MapaIP -Delimiter ';' -Encoding UTF8)) {
    if (-not $m.ip) { continue }
    if ($m.reloj)  { $ipPorNombre[$m.reloj.Trim()]  = $m.ip.Trim() }
    if ($m.serial) { $ipPorSerial[$m.serial.Trim()] = $m.ip.Trim() }
}

$cred = Get-Credential -Message "Usuario y clave de ADMINISTRADOR de los relojes Control iD"
$usuarioReloj = $cred.UserName.TrimStart('\')
$claveReloj   = $cred.GetNetworkCredential().Password

$esquema = if ($Https) { 'https' } else { 'http' }
$modo    = if ($Borrar) { 'BORRAR' } else { 'SOLO VERIFICAR' }
$log     = Join-Path (Split-Path -Parent (Resolve-Path $Archivo)) ("resultado_relojes_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))
$salida  = New-Object System.Collections.Generic.List[object]

function Normalizar([string]$s) {
    if (-not $s) { return '' }
    # algunos relojes devuelven la Ñ rota (U+FFFD o '?'): se toma como N
    $s = $s.ToUpperInvariant().Replace([string][char]0xFFFD, 'N').Replace('?', 'N').Normalize([Text.NormalizationForm]::FormD)
    $s = (-join ($s.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' }))
    return (($s -replace '[^A-Z0-9 ]', ' ') -replace '\s+', ' ').Trim()
}

function Llamar($base, $ruta, $cuerpo) {
    $json = $cuerpo | ConvertTo-Json -Depth 6 -Compress
    return Invoke-RestMethod -Method Post -Uri ($base + $ruta) -ContentType 'application/json' -Body $json -TimeoutSec $TimeoutSeg
}

function PuertoAbierto([string]$h, [int]$puerto, [int]$ms = 3000) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $tcp.BeginConnect($h, $puerto, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($ms, $false)) { return $false }
        $tcp.EndConnect($ar); return $true
    } catch { return $false } finally { $tcp.Close() }
}

function Registrar($reloj, $hostR, $f, $idR, $nomR, $accion, $resultado) {
    $salida.Add([pscustomobject]@{ reloj = $reloj; host = $hostR; id_persona = $f.id_persona; persona = "$($f.apellido) $($f.nombre)".Trim();
                                   id_en_reloj = $idR; nombre_en_reloj = $nomR; accion = $accion; resultado = $resultado })
}
function GuardarLog { $salida | Export-Csv -Path $log -NoTypeInformation -Encoding UTF8 -Delimiter ';' }

Write-Host "Modo: $modo   Filas: $($filas.Count)" -ForegroundColor Cyan

# se agrupa por serial + nombre: puede haber relojes sin serial o con el serial repetido
$grupos = @($filas | Group-Object { "{0}|{1}" -f $_.serial, $_.reloj.Trim() })
$nro = 0
foreach ($grupo in $grupos) {
    $nro++
    $serial      = "$($grupo.Group[0].serial)".Trim()
    $nombreReloj = $grupo.Group[0].reloj.Trim()
    $hostReloj   = if ($ipPorNombre.ContainsKey($nombreReloj)) { $ipPorNombre[$nombreReloj] } elseif ($serial) { $ipPorSerial[$serial] } else { $null }

    if (-not $hostReloj) {
        foreach ($f in $grupo.Group) { Registrar $nombreReloj '' $f '' '' 'NADA' 'SIN IP en el mapa' }
        Write-Host "`n== [$nro/$($grupos.Count)] $nombreReloj : SIN IP en el mapa, se saltea" -ForegroundColor Red
        GuardarLog; continue
    }
    $p    = if ($Puerto -gt 0) { $Puerto } elseif ($Https) { 443 } else { 80 }
    $base = "{0}://{1}:{2}" -f $esquema, $hostReloj, $p
    Write-Host ("`n== [{0}/{1}] {2} ({3}) - {4} personas" -f $nro, $grupos.Count, $nombreReloj, $base, $grupo.Count) -ForegroundColor Yellow

    $motivoSalteo = $null
    if ($Excluir -contains $nombreReloj)        { $motivoSalteo = 'EXCLUIDO por parametro -Excluir' }
    elseif (-not (PuertoAbierto $hostReloj $p)) { $motivoSalteo = "SIN CONEXION al puerto $p (3 s)" }
    if ($motivoSalteo) {
        foreach ($f in $grupo.Group) { Registrar $nombreReloj $hostReloj $f '' '' 'NADA' $motivoSalteo }
        Write-Host "   $motivoSalteo - se saltea" -ForegroundColor Red
        GuardarLog; continue
    }

    try {
        $sesion = (Llamar $base '/login.fcgi' @{ login = $usuarioReloj; password = $claveReloj }).session
        if (-not $sesion) { throw "login sin sesión" }
    } catch {
        $msg = $_.Exception.Message
        foreach ($f in $grupo.Group) { Registrar $nombreReloj $hostReloj $f '' '' 'NADA' "ERROR LOGIN: $msg" }
        Write-Host "   ERROR de login: $msg" -ForegroundColor Red
        GuardarLog; continue
    }
    $q = "?session=$sesion"

    foreach ($f in $grupo.Group) {
        $persona  = "$($f.apellido) $($f.nombre)".Trim()
        $apellido = (Normalizar $f.apellido).Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Select-Object -First 1
        $candidatos = @{}; $erroresConsulta = 0; $ultimoError = ''

        foreach ($valor in @($f.id_reloj, $f.dni) | Where-Object { $_ -and $_ -ne 'NULL' } | Select-Object -Unique) {
            $where = @()
            if ($valor -match '^\d+$') { $where += , @{ users = @{ id = [long]$valor } } }
            $where += , @{ users = @{ registration = [string]$valor } }
            foreach ($w in $where) {
                try {
                    $r = Llamar $base ('/load_objects.fcgi' + $q) @{ object = 'users'; where = $w }
                    foreach ($u in @($r.users)) { if ($u) { $candidatos["$($u.id)"] = $u } }
                } catch { $erroresConsulta++; $ultimoError = $_.Exception.Message }
            }
        }

        $accion = 'NADA'; $resultado = ''; $idR = ''; $nomR = ''
        if ($candidatos.Count -eq 0 -and $erroresConsulta -gt 0) {
            # importante: un error de consulta NO es lo mismo que "no está"
            $resultado = "ERROR AL CONSULTAR ($erroresConsulta consultas fallaron): $ultimoError"
        } elseif ($candidatos.Count -eq 0) {
            $resultado = 'NO ESTA EN EL RELOJ'
        } else {
            $coinciden = @($candidatos.Values | Where-Object { (Normalizar $_.name).Contains($apellido) })
            $idR  = ($candidatos.Values | ForEach-Object { $_.id })   -join '|'
            $nomR = ($candidatos.Values | ForEach-Object { $_.name }) -join '|'
            # varias coincidencias solo se aceptan si son la MISMA persona cargada más de una vez
            # (p.ej. una con id = legajo y otra con id = DNI). El reloj a veces corta el nombre:
            # se acepta el comienzo exacto si tiene al menos 15 caracteres.
            $nombreOrigen = Normalizar $persona
            $mismoNombre  = { param($n) $n = Normalizar $n; ($n -eq $nombreOrigen) -or ($n.Length -ge 15 -and $nombreOrigen.StartsWith($n)) }
            $mismaPersona = ($coinciden.Count -gt 1) -and (@($coinciden | Where-Object { -not (& $mismoNombre $_.name) }).Count -eq 0)

            if ($coinciden.Count -eq 0 -or ($coinciden.Count -gt 1 -and -not $mismaPersona)) {
                $resultado = "NO SE BORRA: el nombre no coincide o hay $($coinciden.Count) coincidencias distintas - revisar a mano"
            } elseif (-not $Borrar) {
                $accion = 'BORRARIA'; $resultado = "encontrado id=" + (($coinciden | ForEach-Object { $_.id }) -join '+')
            } else {
                $okTodos = $true; $detalles = @()
                foreach ($uc in $coinciden) {
                    try {
                        $uid = [long]$uc.id
                        # credenciales y datos asociados (si no existen, el reloj responde changes=0)
                        foreach ($obj in 'cards', 'templates', 'user_roles', 'user_groups') {
                            try { Llamar $base ('/destroy_objects.fcgi' + $q) @{ object = $obj; where = @{ $obj = @{ user_id = $uid } } } | Out-Null } catch { }
                        }
                        try { Llamar $base ('/user_destroy_image.fcgi' + $q) @{ user_ids = @($uid) } | Out-Null } catch { }
                        # el usuario
                        $d = Llamar $base ('/destroy_objects.fcgi' + $q) @{ object = 'users'; where = @{ users = @{ id = $uid } } }
                        # verificación: se vuelve a consultar
                        $quedo = @((Llamar $base ('/load_objects.fcgi' + $q) @{ object = 'users'; where = @{ users = @{ id = $uid } } }).users | Where-Object { $_ })
                        if ($quedo.Count -eq 0) { $detalles += "id $uid ok (changes=$($d.changes))" }
                        else { $okTodos = $false; $detalles += "id $uid SIGUE EN EL RELOJ" }
                    } catch {
                        $okTodos = $false; $detalles += "id $uid ERROR: $($_.Exception.Message)"
                    }
                }
                $accion = if ($okTodos) { 'BORRADO' } else { 'ERROR' }
                $resultado = $detalles -join '; '
            }
        }
        Write-Host ("   {0,-8} {1,-35} {2,-9} {3}" -f $f.id_persona, $persona, $accion, $resultado)
        Registrar $nombreReloj $hostReloj $f $idR $nomR $accion $resultado
    }
    try { Llamar $base ('/logout.fcgi' + $q) @{} | Out-Null } catch { }
    GuardarLog
}

GuardarLog
Write-Host "`nResultado guardado en: $log" -ForegroundColor Cyan
$salida | Group-Object accion | ForEach-Object { Write-Host ("  {0,-9} {1}" -f $_.Name, $_.Count) }
