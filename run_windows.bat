@echo off
python -m foodbridge_app.seed
python -m uvicorn foodbridge_app.main:app --host 127.0.0.1 --port 8000
