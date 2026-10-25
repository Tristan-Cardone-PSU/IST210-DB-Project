# =========================================================================
# Azure SQL Metro Bridge Server (Native Windows PowerShell)
# Powers the Cloud SQL Portal with real-time connectivity to Azure SQL
# Zero external dependencies (uses built-in .NET HttpListener & SqlClient)
# =========================================================================

$port = 8080
$root = $PSScriptRoot
if (-not $root) { $root = "C:\Users\Windows\DB-Project" }

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")

try {
    $listener.Start()
    Write-Host "[BRIDGE] Azure SQL Metro Bridge Server active at http://localhost:$port/" -ForegroundColor Green
    Write-Host "[BRIDGE] Serving portal files from $root" -ForegroundColor Cyan
} catch {
    Write-Host "[BRIDGE ERROR] Could not start listener: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Build-ConnectionString($server, $port, $database, $user, $password) {
    if (-not $port) { $port = "1433" }
    if (-not $database) { $database = "master" }
    return "Server=tcp:$server,$port;Initial Catalog=$database;User ID=$user;Password=$password;Encrypt=True;TrustServerCertificate=False;Connection Timeout=20;"
}

function Send-JsonResponse($response, $statusCode, $data) {
    $json = $data | ConvertTo-Json -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $response.StatusCode = $statusCode
    $response.ContentType = "application/json; charset=utf-8"
    $response.AddHeader("Access-Control-Allow-Origin", "*")
    $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $response.AddHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.OutputStream.Close()
}

function Send-FileResponse($response, $filePath, $contentType) {
    if (Test-Path $filePath) {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $response.StatusCode = 200
        $response.ContentType = $contentType
        $response.AddHeader("Cache-Control", "no-store, no-cache, must-revalidate")
        $response.AddHeader("Access-Control-Allow-Origin", "*")
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $response.StatusCode = 404
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("File Not Found")
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    $response.OutputStream.Close()
}

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $url = $request.Url.LocalPath
        $method = $request.HttpMethod

        # CORS Preflight
        if ($method -eq "OPTIONS") {
            $response.StatusCode = 204
            $response.AddHeader("Access-Control-Allow-Origin", "*")
            $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            $response.AddHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
            $response.OutputStream.Close()
            continue
        }

        # API: Status
        if ($url -eq "/api/status" -and $method -eq "GET") {
            Send-JsonResponse $response 200 @{
                status = "online"
                port = $port
                timestamp = (Get-Date).ToString("o")
            }
            continue
        }

        # API: Connect & Inspect Databases / Tables
        if ($url -eq "/api/connect" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd() | ConvertFrom-Json
            $reader.Close()

            $connStr = Build-ConnectionString $body.server $body.port $body.database $body.user $body.password
            $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $conn.Open()
                $sw.Stop()

                # Get available databases
                $databases = @()
                try {
                    $cmdDb = $conn.CreateCommand()
                    $cmdDb.CommandText = "SELECT name FROM sys.databases WHERE name NOT IN ('model', 'tempdb') ORDER BY name"
                    $rDb = $cmdDb.ExecuteReader()
                    while ($rDb.Read()) { $databases += $rDb["name"].ToString() }
                    $rDb.Close()
                } catch {}

                # Get tables in current database
                $tables = @()
                $columns = @()
                $foreignKeys = @()
                if ($body.database -and $body.database -ne "master") {
                    try {
                        $cmdTbl = $conn.CreateCommand()
                        $cmdTbl.CommandText = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME"
                        $rTbl = $cmdTbl.ExecuteReader()
                        while ($rTbl.Read()) { $tables += $rTbl["TABLE_NAME"].ToString() }
                        $rTbl.Close()

                        $cmdCol = $conn.CreateCommand()
                        $cmdCol.CommandText = "SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS ORDER BY TABLE_NAME, ORDINAL_POSITION"
                        $rCol = $cmdCol.ExecuteReader()
                        while ($rCol.Read()) {
                            $columns += @{
                                tableName = $rCol["TABLE_NAME"].ToString()
                                columnName = $rCol["COLUMN_NAME"].ToString()
                                dataType = $rCol["DATA_TYPE"].ToString()
                                isNullable = $rCol["IS_NULLABLE"].ToString()
                            }
                        }
                        $rCol.Close()

                        $cmdFk = $conn.CreateCommand()
                        $cmdFk.CommandText = @"
SELECT 
    f.name AS ForeignKey,
    OBJECT_NAME(f.parent_object_id) AS TableName,
    COL_NAME(fc.parent_object_id, fc.parent_column_id) AS ColumnName,
    OBJECT_NAME (f.referenced_object_id) AS ReferenceTableName,
    COL_NAME(fc.referenced_object_id, fc.referenced_column_id) AS ReferenceColumnName,
    delete_referential_action_desc AS DeleteRule
FROM sys.foreign_keys AS f
INNER JOIN sys.foreign_key_columns AS fc ON f.OBJECT_ID = fc.constraint_object_id
"@
                        $rFk = $cmdFk.ExecuteReader()
                        while ($rFk.Read()) {
                            $foreignKeys += @{
                                foreignKey = $rFk["ForeignKey"].ToString()
                                tableName = $rFk["TableName"].ToString()
                                columnName = $rFk["ColumnName"].ToString()
                                referenceTable = $rFk["ReferenceTableName"].ToString()
                                referenceColumn = $rFk["ReferenceColumnName"].ToString()
                                deleteRule = $rFk["DeleteRule"].ToString()
                            }
                        }
                        $rFk.Close()
                    } catch {}
                }

                $conn.Close()

                Send-JsonResponse $response 200 @{
                    success = $true
                    message = "Connected to Azure SQL server successfully!"
                    latencyMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
                    serverVersion = $conn.ServerVersion
                    databases = $databases
                    currentDatabase = $body.database
                    tables = $tables
                    columns = $columns
                    foreignKeys = $foreignKeys
                }
            } catch {
                Send-JsonResponse $response 200 @{
                    success = $false
                    error = $_.Exception.Message
                }
            }
            continue
        }

        # API: Query (SELECT)
        if ($url -eq "/api/query" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd() | ConvertFrom-Json
            $reader.Close()

            $connStr = Build-ConnectionString $body.server $body.port $body.database $body.user $body.password
            $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $conn.Open()
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = $body.sql
                $r = $cmd.ExecuteReader()

                $rows = @()
                $colNames = @()
                for ($i = 0; $i -lt $r.FieldCount; $i++) {
                    $colNames += $r.GetName($i)
                }

                while ($r.Read()) {
                    $row = [ordered]@{}
                    foreach ($col in $colNames) {
                        $val = $r[$col]
                        if ($val -eq [System.DBNull]::Value) {
                            $row[$col] = $null
                        } elseif ($val -is [System.DateTime]) {
                            $row[$col] = $val.ToString("yyyy-MM-dd")
                        } else {
                            $row[$col] = $val
                        }
                    }
                    $rows += $row
                }
                $r.Close()
                $conn.Close()
                $sw.Stop()

                Send-JsonResponse $response 200 @{
                    success = $true
                    columns = $colNames
                    rows = $rows
                    count = $rows.Count
                    latencyMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
                }
            } catch {
                Send-JsonResponse $response 200 @{
                    success = $false
                    error = $_.Exception.Message
                }
            }
            continue
        }

        # API: Execute (INSERT / UPDATE / DELETE)
        if ($url -eq "/api/execute" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd() | ConvertFrom-Json
            $reader.Close()

            $connStr = Build-ConnectionString $body.server $body.port $body.database $body.user $body.password
            $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $conn.Open()
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = $body.sql
                $rowsAffected = $cmd.ExecuteNonQuery()
                $conn.Close()
                $sw.Stop()

                Send-JsonResponse $response 200 @{
                    success = $true
                    rowsAffected = $rowsAffected
                    latencyMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
                }
            } catch [System.Data.SqlClient.SqlException] {
                $isFkConflict = ($_.Exception.Number -eq 547)
                Send-JsonResponse $response 200 @{
                    success = $false
                    isForeignKeyConflict = $isFkConflict
                    errorNumber = $_.Exception.Number
                    error = $_.Exception.Message
                }
            } catch {
                Send-JsonResponse $response 200 @{
                    success = $false
                    error = $_.Exception.Message
                }
            }
            continue
        }

        # Static File Serving
        # Keep the separately stored SQL login file out of browser-served paths.
        if ($url -eq "/LOGIN_INFO.txt") {
            $response.StatusCode = 404
            $response.OutputStream.Close()
            continue
        }

        $filePath = ""
        $contentType = "text/plain"

        if ($url -eq "/" -or $url -eq "/index.html") {
            $filePath = Join-Path $root "index.html"
            $contentType = "text/html; charset=utf-8"
        } elseif ($url -eq "/style.css") {
            $filePath = Join-Path $root "style.css"
            $contentType = "text/css; charset=utf-8"
        } elseif ($url -eq "/app.js") {
            $filePath = Join-Path $root "app.js"
            $contentType = "application/javascript; charset=utf-8"
        } elseif ($url -eq "/schema.sql") {
            $filePath = Join-Path $root "schema.sql"
            $contentType = "text/plain; charset=utf-8"
        } else {
            $cleanName = $url.TrimStart('/')
            $target = Join-Path $root $cleanName
            if (Test-Path $target) {
                $filePath = $target
                if ($cleanName.EndsWith(".html")) { $contentType = "text/html; charset=utf-8" }
                elseif ($cleanName.EndsWith(".css")) { $contentType = "text/css; charset=utf-8" }
                elseif ($cleanName.EndsWith(".js")) { $contentType = "application/javascript; charset=utf-8" }
                elseif ($cleanName.EndsWith(".json")) { $contentType = "application/json; charset=utf-8" }
            }
        }

        if ($filePath -and (Test-Path $filePath)) {
            Send-FileResponse $response $filePath $contentType
        } else {
            $response.StatusCode = 404
            $errBytes = [System.Text.Encoding]::UTF8.GetBytes("Not Found: $url")
            $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            $response.OutputStream.Close()
        }
    } catch {
        # Keep listener alive on connection errors
    }
}
