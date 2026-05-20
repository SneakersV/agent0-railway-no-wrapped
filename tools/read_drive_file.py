import argparse
import io
import json
import os
from typing import Any

import pandas as pd


SERVICE_ACCOUNT_FILE = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "/a0/credentials.json")
SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]
GOOGLE_SHEET_XLSX_MIME = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


def get_drive_service():
    """Authenticates and returns the Google Drive service."""
    if not os.path.exists(SERVICE_ACCOUNT_FILE):
        return None, f"credentials.json not found at {SERVICE_ACCOUNT_FILE}"

    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build

        creds = service_account.Credentials.from_service_account_file(
            SERVICE_ACCOUNT_FILE,
            scopes=SCOPES,
        )
        return build("drive", "v3", credentials=creds), None
    except Exception as exc:
        return None, str(exc)


def _download_to_bytes(service: Any, file_id: str, mime_type: str) -> io.BytesIO:
    from googleapiclient.http import MediaIoBaseDownload

    if mime_type == "application/vnd.google-apps.spreadsheet":
        request = service.files().export_media(fileId=file_id, mimeType=GOOGLE_SHEET_XLSX_MIME)
    else:
        request = service.files().get_media(fileId=file_id)

    buffer = io.BytesIO()
    downloader = MediaIoBaseDownload(buffer, request)
    done = False
    while not done:
        _, done = downloader.next_chunk()
    buffer.seek(0)
    return buffer


def _clean_dataframe(df: pd.DataFrame, max_rows: int, max_cols: int) -> pd.DataFrame:
    df = df.dropna(axis=0, how="all").dropna(axis=1, how="all")
    if df.empty:
        return df

    # If pandas created unnamed numeric columns, promote the strongest early row to headers.
    unnamed_ratio = sum(str(col).startswith("Unnamed:") for col in df.columns) / max(len(df.columns), 1)
    if unnamed_ratio > 0.5:
        sample = df.head(20)
        best_index = None
        best_score = -1
        for index, row in sample.iterrows():
            values = [str(value).strip() for value in row.tolist() if str(value).strip() and str(value) != "nan"]
            text_count = sum(any(ch.isalpha() for ch in value) for value in values)
            score = text_count * 2 + len(values)
            if len(values) >= 2 and score > best_score:
                best_score = score
                best_index = index

        if best_index is not None:
            headers = [
                str(value).strip() if str(value).strip() and str(value) != "nan" else f"Column {idx + 1}"
                for idx, value in enumerate(df.loc[best_index].tolist())
            ]
            df = df.loc[best_index + 1 :].copy()
            df.columns = headers

    df = df.head(max_rows).iloc[:, :max_cols]
    df = df.where(pd.notnull(df), None)
    return df


def _value_to_json(value: Any) -> Any:
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def _sheet_payload(sheet_name: str, df: pd.DataFrame, max_rows: int, max_cols: int) -> dict[str, Any]:
    cleaned = _clean_dataframe(df, max_rows=max_rows, max_cols=max_cols)
    headers = [str(col).strip() for col in cleaned.columns.tolist()]
    rows = [
        {headers[idx]: _value_to_json(value) for idx, value in enumerate(row)}
        for row in cleaned.itertuples(index=False, name=None)
    ]
    markdown = ""
    if not cleaned.empty:
        try:
            markdown = cleaned.to_markdown(index=False)
        except ImportError:
            markdown = cleaned.to_csv(index=False)
    return {
        "sheet": sheet_name,
        "headers": headers,
        "row_count_returned": len(rows),
        "rows": rows,
        "markdown_preview": markdown,
    }


def _read_spreadsheet(
    buffer: io.BytesIO,
    file_name: str,
    sheet_name: str | None,
    max_rows: int,
    max_cols: int,
    max_sheets: int,
) -> list[dict[str, Any]]:
    extension = file_name.rsplit(".", 1)[-1].lower() if "." in file_name else ""

    if extension == "csv":
        df = pd.read_csv(buffer, dtype=object)
        return [_sheet_payload("CSV", df, max_rows=max_rows, max_cols=max_cols)]

    if extension == "xls":
        engine = "xlrd"
    else:
        engine = "openpyxl"

    if sheet_name:
        df = pd.read_excel(buffer, sheet_name=sheet_name, dtype=object, engine=engine)
        return [_sheet_payload(sheet_name, df, max_rows=max_rows, max_cols=max_cols)]

    sheets = pd.read_excel(buffer, sheet_name=None, dtype=object, engine=engine)
    return [
        _sheet_payload(name, df, max_rows=max_rows, max_cols=max_cols)
        for name, df in list(sheets.items())[:max_sheets]
    ]


def read_drive_file(
    file_id: str,
    sheet_name: str | None = None,
    max_rows: int = 80,
    max_cols: int = 30,
    max_sheets: int = 6,
    output_format: str = "markdown",
) -> str:
    """
    Reads a Google Drive file by ID and returns source-grounded table context.

    The function intentionally does not calculate business answers. It gives the LLM
    enough raw rows, headers, sheet names, and source metadata to calculate in-context.
    """
    service, error = get_drive_service()
    if error:
        return f"Error: {error}"

    try:
        file_meta = service.files().get(
            fileId=file_id,
            fields="id,name,mimeType,webViewLink,size,modifiedTime",
        ).execute()
        mime_type = file_meta.get("mimeType", "")
        file_name = file_meta.get("name", "unknown_file")
        buffer = _download_to_bytes(service, file_id, mime_type)

        is_table = (
            mime_type == "application/vnd.google-apps.spreadsheet"
            or file_name.lower().endswith((".xlsx", ".xls", ".csv"))
        )

        if is_table:
            sheets = _read_spreadsheet(
                buffer,
                file_name=file_name,
                sheet_name=sheet_name,
                max_rows=max_rows,
                max_cols=max_cols,
                max_sheets=max_sheets,
            )
            payload = {
                "file": {
                    "id": file_meta.get("id"),
                    "name": file_name,
                    "mime_type": mime_type,
                    "web_view_link": file_meta.get("webViewLink"),
                    "modified_time": file_meta.get("modifiedTime"),
                },
                "limits": {
                    "max_rows_per_sheet": max_rows,
                    "max_cols_per_sheet": max_cols,
                    "max_sheets": max_sheets,
                },
                "sheets": sheets,
                "instruction": (
                    "Use these rows as the source of truth. If a calculation needs rows "
                    "outside these limits, ask for a narrower sheet/range instead of guessing."
                ),
            }
        else:
            text = buffer.read().decode("utf-8", errors="replace")
            payload = {
                "file": {
                    "id": file_meta.get("id"),
                    "name": file_name,
                    "mime_type": mime_type,
                    "web_view_link": file_meta.get("webViewLink"),
                    "modified_time": file_meta.get("modifiedTime"),
                },
                "text_preview": text[:20000],
                "truncated": len(text) > 20000,
            }

        if output_format == "json":
            return json.dumps(payload, ensure_ascii=False, default=str)

        if "sheets" not in payload:
            return (
                f"File Name: {payload['file']['name']}\n"
                f"Drive Link: {payload['file'].get('web_view_link')}\n"
                f"Text Preview:\n{payload['text_preview']}"
            )

        parts = [
            f"File Name: {payload['file']['name']}",
            f"Drive Link: {payload['file'].get('web_view_link')}",
            "Use the following sheet previews as raw source data for calculation.",
        ]
        for sheet in payload["sheets"]:
            parts.extend(
                [
                    "",
                    f"Sheet: {sheet['sheet']}",
                    f"Headers: {', '.join(sheet['headers'])}",
                    sheet["markdown_preview"] or "(empty sheet)",
                ]
            )
        return "\n".join(parts)
    except Exception as exc:
        return f"Error reading file {file_id}: {exc}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Read a Google Drive file for Agent0 LLM context.")
    parser.add_argument("--file-id", required=True, help="Google Drive file ID")
    parser.add_argument("--sheet", default=None, help="Optional sheet name")
    parser.add_argument("--max-rows", type=int, default=80)
    parser.add_argument("--max-cols", type=int, default=30)
    parser.add_argument("--max-sheets", type=int, default=6)
    parser.add_argument("--format", choices=["markdown", "json"], default="markdown")
    args = parser.parse_args()

    print(
        read_drive_file(
            args.file_id,
            sheet_name=args.sheet,
            max_rows=args.max_rows,
            max_cols=args.max_cols,
            max_sheets=args.max_sheets,
            output_format=args.format,
        )
    )


if __name__ == "__main__":
    main()
