import os
import json
from supabase import create_client, Client
from read_drive_file import read_drive_file

# Configuration - Environment Variables (Best Practice)
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("WARNING: SUPABASE_URL or SUPABASE_KEY not found in environment variables.")

def build_knowledge_base():
    print("Connecting to Supabase...")
    try:
        supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
        # Fetch file metadata
        response = supabase.table("file_search_storage").select("*").execute()
        files = response.data
    except Exception as e:
        return f"Error connecting to Supabase: {str(e)}"

    if not files:
        return "No files found in Supabase table 'file_search_storage'."

    knowledge_entries = []
    print(f"Found {len(files)} files. Processing...")

    for file_record in files:
        drive_id = file_record.get('drive_file_id') # Adjust column name if needed
        file_name = file_record.get('file_name', 'Unknown')
        
        if not drive_id:
            print(f"Skipping {file_name}: No Drive ID")
            continue

        print(f"Reading Drive File: {file_name} ({drive_id})")
        content = read_drive_file(drive_id)
        
        # Create a structured entry
        entry = {
            "source": "Google Drive",
            "file_name": file_name,
            "drive_id": drive_id,
            "supabase_id": file_record.get('id'),
            "content_summary": content[:500] + "..." if len(content) > 500 else content, # Truncate for now
            "full_content": content # Keep full content for the memory file
        }
        knowledge_entries.append(entry)

    # Save to a Markdown file in the persistent memory directory
    output_path = "/per/memory/knowledge_base.md"
    
    # Ensure directory exists
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("# Điện Máy Thăng Long - Knowledge Base\n\n")
        f.write("> **System Note**: This is the structured index of all company files. Use this to locate documents and understand their contents before answering questions.\n\n")
        f.write("| File Name | Drive Link | Summary/Content Preview |\n")
        f.write("| :--- | :--- | :--- |\n")
        
        for entry in knowledge_entries:
            # Create a direct link (if View Link is available, else construct it)
            drive_link = f"https://docs.google.com/spreadsheets/d/{entry['drive_id']}" if "spreadsheet" in entry.get('mime_type', '') else f"https://drive.google.com/file/d/{entry['drive_id']}/view"
            
            # Clean summary for Markdown table
            summary = entry['content_summary'].replace("\n", "<br>").replace("|", "-")
            
            f.write(f"| **{entry['file_name']}** | [Open File]({drive_link}) | {summary} |\n")

    return f"Successfully generated {output_path} with {len(knowledge_entries)} entries. Agent Zero will now have access to this knowledge."

if __name__ == "__main__":
    result = build_knowledge_base()
    print(result)
