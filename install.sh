#!/bin/bash
echo "🔧 در حال نصب پیش‌نیازها..."
pip install -r requirements.txt

echo "🚀 اجرای اسکریپت ترکیب‌کننده..."
python3 combine.py
