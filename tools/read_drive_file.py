import os
import io
from googleapiclient.discovery import build
from google.oauth2 import service_account
from googleapiclient.http import MediaIoBaseDownload
import pandas as pd

# Path to the service account key inside the container
# Check env first, then default to /a0/credentials.json
SERVICE_ACCOUNT_FILE = os.getenv('GOOGLE_APPLICATION_CREDENTIALS', '/a0/credentials.json')
SCOPES = ['https://www.googleapis.com/auth/drive.readonly']

def get_drive_service():
    """Authenticates and returns the Google Drive service."""
    if not os.path.exists(SERVICE_ACCOUNT_FILE):
        return None, "credentials.json not found"
    
    try:
        creds = service_account.Credentials.from_service_account_file(
            SERVICE_ACCOUNT_FILE, scopes=SCOPES)
        return build('drive', 'v3', credentials=creds), None
    except Exception as e:
        return None, str(e)

def read_drive_file(file_id):
    """
    Reads a file from Google Drive by ID. 
    Supports Google Sheets (exported as CSV) and plain text/CSV files.
    Returns the content as a string.
    """
    service, error = get_drive_service()
    if error:
        return f"Error: {error}"

    try:
        # Get file metadata to determine type
        file_meta = service.files().get(fileId=file_id).execute()
        mime_type = file_meta.get('mimeType', '')
        name = file_meta.get('name', 'unknown_file')

        request = None
        if 'application/vnd.google-apps.spreadsheet' in mime_type:
            # Export Google Sheet to CSV
            request = service.files().export_media(fileId=file_id, mimeType='text/csv')
        elif 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' in mime_type:
            # Excel file - download binary
            request = service.files().get_media(fileId=file_id)
            # Todo: Handle Excel parsing if needed, but for now returned as binary note
            # Better approach: Read into pandas if possible in-memory
        else:
            # Text/CSV or other download
            request = service.files().get_media(fileId=file_id)

        fh = io.BytesIO()
        downloader = MediaIoBaseDownload(fh, request)
        done = False
        while done is False:
            status, done = downloader.next_chunk()

        fh.seek(0)
        
        # Parse content based on type
        if 'spreadsheet' in mime_type or name.endswith('.xlsx') or name.endswith('.csv'):
            try:
                # Try reading as CSV/Excel
                if name.endswith('.xlsx'):
                     df = pd.read_excel(fh)
                else:
                     df = pd.read_csv(fh)
                return f"File Name: {name}\\nContent:\\n{df.to_markdown(index=False)}"
            except Exception as parse_error:
                return f"Downloaded {name} but failed to parse as table: {parse_error}"
        else:
            # Try decoding as text
            try:
                content = fh.read().decode('utf-8')
                return f"File Name: {name}\\nContent:\\n{content}"
            except:
                return f"File {name} downloaded but is likely binary/image. Cannot read text."

    except Exception as e:
        return f"Error reading file {file_id}: {str(e)}"

# Test execution (optional)
if __name__ == "__main__":
    # Replace with a valid ID to test
    print("Drive Reader Tool Loaded")
