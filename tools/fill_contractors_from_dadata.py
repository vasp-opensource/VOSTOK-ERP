#!/usr/bin/env python3
"""Fill empty Contractors fields by INN from DaData.

Requires one MySQL Python driver:
  py -m pip install pymysql
or:
  py -m pip install mysql-connector-python

Environment variables:
  VOSTOK_DB_HOST, VOSTOK_DB_PORT, VOSTOK_DB_NAME, VOSTOK_DB_USER, VOSTOK_DB_PASSWORD
  DADATA_TOKEN, optional DADATA_SECRET

Example:
  py tools/fill_contractors_from_dadata.py --limit 100
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import urllib.request
from typing import Any


DADATA_URL = "https://suggestions.dadata.ru/suggestions/api/4_1/rs/findById/party"


def load_mysql_driver():
    try:
        import mysql.connector  # type: ignore

        return "mysql-connector", mysql.connector
    except ImportError:
        pass

    try:
        import pymysql  # type: ignore

        return "pymysql", pymysql
    except ImportError:
        pass

    raise RuntimeError(
        "No MySQL Python driver found. Install one: "
        "py -m pip install mysql-connector-python"
    )


def connect_mysql(args: argparse.Namespace):
    driver_name, driver = load_mysql_driver()
    common = {
        "host": args.db_host,
        "port": args.db_port,
        "user": args.db_user,
        "password": args.db_password,
        "database": args.db_name,
    }

    if driver_name == "pymysql":
        return driver.connect(
            **common,
            charset="utf8mb4",
            cursorclass=driver.cursors.DictCursor,
            autocommit=False,
        )

    return driver.connect(**common, charset="utf8mb4", use_unicode=True)


def cursor_dict(connection):
    module_name = connection.__class__.__module__
    if module_name.startswith("mysql.connector"):
        return connection.cursor(dictionary=True)
    return connection.cursor()


def dadata_date(value: Any) -> str | None:
    if value in (None, ""):
        return None
    try:
        utc_tz = getattr(dt, "UTC", dt.timezone.utc)
        return dt.datetime.fromtimestamp(int(value) / 1000, utc_tz).strftime("%Y-%m-%d")
    except (TypeError, ValueError, OSError):
        return None


def find_party(token: str, secret: str | None, inn: str, kpp: str | None) -> dict[str, Any] | None:
    payload: dict[str, Any] = {"query": inn}
    if kpp:
        payload["kpp"] = kpp

    headers = {
        "Authorization": f"Token {token}",
        "Content-Type": "application/json; charset=utf-8",
        "Accept": "application/json",
    }
    if secret:
        headers["X-Secret"] = secret

    request = urllib.request.Request(
        DADATA_URL,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )

    with urllib.request.urlopen(request, timeout=30) as response:
        result = json.loads(response.read().decode("utf-8"))

    suggestions = result.get("suggestions") or []
    if not suggestions:
        return None

    if kpp:
        for suggestion in suggestions:
            if (suggestion.get("data") or {}).get("kpp") == kpp:
                return suggestion
    return suggestions[0]


def nested(data: dict[str, Any], *keys: str) -> Any:
    current: Any = data
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def select_contractors(connection, limit: int) -> list[dict[str, Any]]:
    sql = """
SELECT
    `id`,
    COALESCE(`INN`, '') AS `INN`,
    COALESCE(`KPP`, '') AS `KPP`
FROM `Contractors`
WHERE `INN` IS NOT NULL
  AND TRIM(`INN`) <> ''
  AND (
        `Short_name` IS NULL OR TRIM(`Short_name`) = ''
     OR TRIM(`Short_name`) = TRIM(`INN`)
     OR `Full_name` IS NULL OR TRIM(`Full_name`) = ''
     OR `KPP` IS NULL OR TRIM(`KPP`) = ''
     OR `OGRN` IS NULL OR TRIM(`OGRN`) = ''
     OR `Director` IS NULL OR TRIM(`Director`) = ''
     OR `Post_address` IS NULL OR TRIM(`Post_address`) = ''
     OR `Status` IS NULL OR TRIM(`Status`) = ''
  )
ORDER BY `id`
LIMIT %s
"""
    with cursor_dict(connection) as cursor:
        cursor.execute(sql, (limit,))
        return list(cursor.fetchall())


def update_contractor(connection, contractor_id: int, values: dict[str, Any]) -> None:
    sql = """
UPDATE `Contractors`
SET
    `Short_name` = CASE
        WHEN `Short_name` IS NULL OR TRIM(`Short_name`) = '' OR TRIM(`Short_name`) = TRIM(`INN`) THEN %s
        ELSE `Short_name`
    END,
    `Full_name` = CASE WHEN `Full_name` IS NULL OR TRIM(`Full_name`) = '' THEN %s ELSE `Full_name` END,
    `KPP` = CASE WHEN `KPP` IS NULL OR TRIM(`KPP`) = '' THEN %s ELSE `KPP` END,
    `OGRN` = CASE WHEN `OGRN` IS NULL OR TRIM(`OGRN`) = '' THEN %s ELSE `OGRN` END,
    `Director` = CASE WHEN `Director` IS NULL OR TRIM(`Director`) = '' THEN %s ELSE `Director` END,
    `Post_address` = CASE WHEN `Post_address` IS NULL OR TRIM(`Post_address`) = '' THEN %s ELSE `Post_address` END,
    `Status` = CASE WHEN `Status` IS NULL OR TRIM(`Status`) = '' THEN %s ELSE `Status` END,
    `Registration_date` = CASE WHEN `Registration_date` IS NULL THEN %s ELSE `Registration_date` END,
    `Liquidation_date` = CASE WHEN `Liquidation_date` IS NULL THEN %s ELSE `Liquidation_date` END,
    `Source_name` = 'dadata',
    `Source_updated_at` = NOW(),
    `updated_at` = NOW()
WHERE `id` = %s
"""
    params = (
        values.get("short_name"),
        values.get("full_name"),
        values.get("kpp"),
        values.get("ogrn"),
        values.get("director"),
        values.get("address"),
        values.get("status"),
        values.get("registration_date"),
        values.get("liquidation_date"),
        contractor_id,
    )
    with cursor_dict(connection) as cursor:
        cursor.execute(sql, params)


def is_duplicate_key_error(exc: Exception) -> bool:
    errno = getattr(exc, "errno", None)
    if errno == 1062:
        return True
    if getattr(exc, "args", None):
        first = exc.args[0]
        if isinstance(first, int) and first == 1062:
            return True
    text = str(exc)
    return "Duplicate entry" in text or "1062" in text


def suggestion_to_values(suggestion: dict[str, Any]) -> dict[str, Any]:
    data = suggestion.get("data") or {}
    short_name = nested(data, "name", "short_with_opf") or suggestion.get("value")
    full_name = nested(data, "name", "full_with_opf") or short_name

    return {
        "short_name": short_name,
        "full_name": full_name,
        "kpp": data.get("kpp"),
        "ogrn": data.get("ogrn"),
        "director": nested(data, "management", "name"),
        "address": nested(data, "address", "unrestricted_value"),
        "status": nested(data, "state", "status"),
        "registration_date": dadata_date(nested(data, "state", "registration_date")),
        "liquidation_date": dadata_date(nested(data, "state", "liquidation_date")),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Fill Contractors data from DaData by INN")
    parser.add_argument("--db-host", default=os.getenv("VOSTOK_DB_HOST"))
    parser.add_argument("--db-port", type=int, default=int(os.getenv("VOSTOK_DB_PORT", "3306")))
    parser.add_argument("--db-name", default=os.getenv("VOSTOK_DB_NAME"))
    parser.add_argument("--db-user", default=os.getenv("VOSTOK_DB_USER"))
    parser.add_argument("--db-password", default=os.getenv("VOSTOK_DB_PASSWORD"))
    parser.add_argument("--dadata-token", default=os.getenv("DADATA_TOKEN"))
    parser.add_argument("--dadata-secret", default=os.getenv("DADATA_SECRET"))
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--dry-run", action="store_true")
    return parser


def require(value: str | None, name: str) -> str:
    if not value:
        raise RuntimeError(f"Set {name} environment variable or pass matching argument")
    return value


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    args.db_host = require(args.db_host, "VOSTOK_DB_HOST")
    args.db_name = require(args.db_name, "VOSTOK_DB_NAME")
    args.db_user = require(args.db_user, "VOSTOK_DB_USER")
    args.dadata_token = require(args.dadata_token, "DADATA_TOKEN")

    connection = connect_mysql(args)
    updated = 0
    not_found = 0
    skipped_duplicates = 0

    try:
        rows = select_contractors(connection, args.limit)
        if not rows:
            print("No Contractors rows require DaData enrichment.")
            return 0

        for row in rows:
            contractor_id = int(row["id"])
            inn = str(row["INN"])
            kpp = str(row.get("KPP") or "")
            suggestion = find_party(args.dadata_token, args.dadata_secret, inn, kpp)
            if suggestion is None:
                print(f"Contractor id={contractor_id} INN={inn}: not found in DaData")
                not_found += 1
                continue

            values = suggestion_to_values(suggestion)
            if args.dry_run:
                print(f"DRY RUN Contractor id={contractor_id} INN={inn}: {values}")
            else:
                try:
                    update_contractor(connection, contractor_id, values)
                    print(f"Contractor id={contractor_id} INN={inn}: updated from DaData")
                    updated += 1
                except Exception as exc:
                    if is_duplicate_key_error(exc):
                        skipped_duplicates += 1
                        print(
                            f"Contractor id={contractor_id} INN={inn}: skipped due to duplicate unique key ({exc})"
                        )
                        continue
                    raise
            if args.dry_run:
                updated += 1

        if args.dry_run:
            connection.rollback()
        else:
            connection.commit()
        print(
            f"Done. Updated={updated} NotFound={not_found} "
            f"SkippedDuplicates={skipped_duplicates} DryRun={args.dry_run}"
        )
        return 0
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        if "cryptography" in str(exc).lower():
            print(
                "Hint: install mysql-connector-python or add cryptography for pymysql: "
                "py -m pip install mysql-connector-python",
                file=sys.stderr,
            )
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
