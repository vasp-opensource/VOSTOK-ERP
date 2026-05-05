@echo off
set VOSTOK_DB_HOST=172.16.1.248
set VOSTOK_DB_PORT=3306
set VOSTOK_DB_NAME=VOSTOK_ERP
set VOSTOK_DB_USER=dadata
set VOSTOK_DB_PASSWORD=MZZXF@OByLfH4t]!
set DADATA_TOKEN=ad334e002cb51abbdd55c5875bceaed515e6907a

rem Install once if needed:
rem py -m pip install mysql-connector-python
rem If you use pymysql instead, install cryptography too:
rem py -m pip install pymysql cryptography

py "C:\Vostok\ERP\tools\fill_contractors_from_dadata.py" --limit 100
