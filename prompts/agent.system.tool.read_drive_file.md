# Tool: read_drive_file

Use this tool when the user asks a calculation, comparison, audit, lookup, or extraction question that depends on data inside a Google Drive file.

## How to call

Run the existing script directly:

```bash
python3 /a0/tools/read_drive_file.py --file-id "<GOOGLE_DRIVE_FILE_ID>" --format markdown --max-rows 120 --max-sheets 8
```

If you already know the sheet:

```bash
python3 /a0/tools/read_drive_file.py --file-id "<GOOGLE_DRIVE_FILE_ID>" --sheet "<SHEET_NAME>" --format markdown --max-rows 200
```

## Required workflow for spreadsheet calculations

1. First identify the file from `/per/memory/knowledge_base.md` or `file_search_storage`.
2. Then call `read_drive_file` with the Drive file ID.
3. Use the returned sheet names, headers, rows, and source link as the source of truth.
4. Do the calculation yourself from the returned rows.
5. In the final answer, mention the file name, sheet name, and the columns you used.

## Accuracy rules

- Do not answer a spreadsheet calculation from vector search snippets alone.
- Do not say "không có dữ liệu" unless you have read the raw file or clearly state that raw file reading failed.
- If the returned preview is insufficient, retry once with a narrower sheet name or higher `--max-rows`.
- If the file is too large or the correct sheet/column is ambiguous, ask one concise follow-up question instead of guessing.
