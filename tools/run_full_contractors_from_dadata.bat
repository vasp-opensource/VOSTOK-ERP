@echo off
set VOSTOK_DB_HOST=172.16.1.248
set VOSTOK_DB_NAME=VOSTOK_ERP
set VOSTOK_DB_USER=dadata
set VOSTOK_DB_PASSWORD=MZZXF@OByLfH4t]!
set DADATA_TOKEN=ad334e002cb51abbdd55c5875bceaed515e6907a
rem If mysql.exe is not in PATH, uncomment and set the actual path:
rem set VOSTOK_MYSQL_PATH=C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe

powershell -ExecutionPolicy Bypass -File "C:\Vostok\ERP\tools\fill_contractors_from_dadata.ps1" -Limit 100