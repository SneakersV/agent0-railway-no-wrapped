import os
import shutil
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
import uvicorn

app = FastAPI()

# Thư mục lưu file tạm. 
# Agent Zero cần được cấu hình để có thể đọc được thư mục này.
UPLOAD_DIR = os.getenv("UPLOAD_DIR", "/app/agent_zero/work_dir/custom_uploads")

# Tạo thư mục nếu chưa tồn tại
os.makedirs(UPLOAD_DIR, exist_ok=True)

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    try:
        # Đường dẫn file đích
        file_path = os.path.join(UPLOAD_DIR, file.filename)
        
        # Lưu file
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        return JSONResponse(status_code=200, content={
            "filename": file.filename,
            "filepath": file_path,
            "message": "File uploaded successfully"
        })
    except Exception as e:
        return JSONResponse(status_code=500, content={"message": str(e)})

@app.get("/health")
def health_check():
    return {"status": "ok"}

if __name__ == "__main__":
    # Chạy trên port 8001 để tránh conflict với Agent Zero chính (thường là 80/8080)
    # Bạn cần expose port này trong Docker hoặc Railway nếu muốn gọi từ ngoài
    port = int(os.getenv("FILE_RECEIVER_PORT", 8001))
    uvicorn.run(app, host="0.0.0.0", port=port)
