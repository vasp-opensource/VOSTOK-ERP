#!/usr/bin/env python3
"""Build a Banks import SQL file from the Bank of Russia ED807 BIK directory.

Usage examples:
  python tools/load_cbr_banks.py --output sql/import_banks_from_cbr.sql
  python tools/load_cbr_banks.py --input path/to/ed807.xml --output sql/import_banks_from_cbr.sql
  python tools/load_cbr_banks.py --input path/to/newbik.zip --output sql/import_banks_from_cbr.sql

The script uses only Python standard library modules. It does not connect to MySQL;
it generates an idempotent SQL file with INSERT ... ON DUPLICATE KEY UPDATE.
"""

from __future__ import annotations

import argparse
import datetime as dt
import io
import sys
import urllib.request
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


CBR_NEWBIK_URL = "https://www.cbr.ru/s/newbik"


def local_name(tag: str) -> str:
    if "}" in tag:
        return tag.rsplit("}", 1)[1]
    return tag


def child_by_name(node: ET.Element, name: str) -> ET.Element | None:
    for child in list(node):
        if local_name(child.tag) == name:
            return child
    return None


def children_by_name(node: ET.Element, name: str) -> list[ET.Element]:
    return [child for child in list(node) if local_name(child.tag) == name]


def attr(node: ET.Element | None, name: str) -> str | None:
    if node is None:
        return None
    value = node.attrib.get(name)
    if value is None:
        return None
    value = value.strip()
    return value or None


def sql_string(value: str | None) -> str:
    if value is None:
        return "NULL"
    escaped = value.replace("\\", "\\\\").replace("'", "''")
    return f"'{escaped}'"


def read_source(input_path: str | None) -> bytes:
    if input_path:
        return Path(input_path).read_bytes()

    request = urllib.request.Request(
        CBR_NEWBIK_URL,
        headers={"User-Agent": "VOSTOK-ERP-BIK-loader/1.0"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def extract_xml(payload: bytes) -> bytes:
    if payload.startswith(b"PK"):
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            xml_names = [name for name in archive.namelist() if name.lower().endswith(".xml")]
            if not xml_names:
                raise ValueError("ZIP archive does not contain XML files")
            xml_names.sort()
            return archive.read(xml_names[0])
    return payload


def parse_banks(xml_payload: bytes) -> tuple[str | None, list[dict[str, str | None]]]:
    root = ET.fromstring(xml_payload)
    ed_date = root.attrib.get("EDDate") or root.attrib.get("CreationDate")
    banks: list[dict[str, str | None]] = []

    for entry in root.iter():
        if local_name(entry.tag) != "BICDirectoryEntry":
            continue

        participant = child_by_name(entry, "ParticipantInfo")
        accounts_parent = child_by_name(entry, "Accounts")
        accounts = children_by_name(accounts_parent, "Account") if accounts_parent is not None else []
        account = next((a for a in accounts if attr(a, "AccountStatus") == "ACAC"), None)
        if account is None and accounts:
            account = accounts[0]

        banks.append(
            {
                "BIK": attr(entry, "BIC"),
                "Bank_name": attr(participant, "NameP"),
                "Short_name": attr(participant, "NameP"),
                "Korrespond_account_number": attr(account, "Account"),
                "Account_status": attr(account, "AccountStatus"),
                "Account_type": attr(account, "RegulationAccountType"),
                "Participant_status": attr(participant, "ParticipantStatus"),
                "Participant_type": attr(participant, "PtType"),
                "Services": attr(participant, "Srvcs"),
                "Exchange_type": attr(participant, "XchType"),
                "Region": attr(participant, "Rgn"),
                "City": attr(participant, "Nnp"),
                "Address": attr(participant, "Adr"),
                "Registration_number": attr(participant, "RegN"),
                "Parent_BIK": attr(participant, "PrntBIC"),
                "Date_in": attr(participant, "DateIn"),
                "Source_updated_at": ed_date,
            }
        )

    return ed_date, [bank for bank in banks if bank["BIK"] and bank["Bank_name"]]


def build_sql(ed_date: str | None, banks: list[dict[str, str | None]]) -> str:
    columns = [
        "BIK",
        "Bank_name",
        "Short_name",
        "Korrespond_account_number",
        "Account_status",
        "Account_type",
        "Participant_status",
        "Participant_type",
        "Services",
        "Exchange_type",
        "Region",
        "City",
        "Address",
        "Registration_number",
        "Parent_BIK",
        "Date_in",
        "Source_updated_at",
    ]
    generated_at = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = [
        "-- Import Banks from Bank of Russia ED807 BIK directory.",
        f"-- Generated at: {generated_at}",
        f"-- ED807 date: {ed_date or 'unknown'}",
        "",
    ]

    if not banks:
        lines.append("-- No banks parsed.")
        return "\n".join(lines) + "\n"

    lines.append(
        "INSERT INTO `Banks` ("
        + ", ".join(f"`{column}`" for column in columns)
        + ")"
    )
    lines.append("VALUES")

    values: list[str] = []
    for bank in banks:
        row = ", ".join(sql_string(bank.get(column)) for column in columns)
        values.append(f"    ({row})")
    lines.append(",\n".join(values))

    update_columns = [column for column in columns if column != "BIK"]
    lines.append("ON DUPLICATE KEY UPDATE")
    lines.append(
        ",\n".join(
            f"    `{column}` = VALUES(`{column}`)" for column in update_columns
        )
        + ";"
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Banks import SQL from CBR ED807 BIK directory")
    parser.add_argument("--input", help="Optional local ED807 XML or ZIP file. If omitted, downloads from CBR.")
    parser.add_argument("--output", default="sql/import_banks_from_cbr.sql", help="Output SQL file path.")
    args = parser.parse_args()

    payload = read_source(args.input)
    xml_payload = extract_xml(payload)
    ed_date, banks = parse_banks(xml_payload)
    sql = build_sql(ed_date, banks)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(sql, encoding="utf-8", newline="\n")
    print(f"Wrote {len(banks)} bank rows to {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
