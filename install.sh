#!/bin/bash

echo "🔧 در حال نصب پیش‌نیازها..."
apt update -y
apt install -y python3 python3-pip nginx

echo "📦 نصب کتابخانه requests برای پایتون..."
pip3 install requests

echo "📁 ساخت پوشه فایل خروجی برای Nginx..."
mkdir -p /var/www/sub

echo "📝 ایجاد فایل پایتون ترکیب‌کننده..."

cat > combine.py << 'EOF'
import requests, base64

def get_links():
    print("🔗 لطفاً لینک‌های سابسکریپشن را وارد کنید. برای پایان، Enter خالی بزنید.\n")
    links = []
    while True:
        link = input(f"🔹 لینک شماره {len(links)+1}: ")
        if not link.strip():
            break
        links.append(link.strip())
    return links

def fetch_and_decode(link):
    try:
        res = requests.get(link, timeout=10)
        decoded = base64.b64decode(res.text).decode('utf-8')
        return decoded
    except Exception as e:
        print(f"❌ خطا در دریافت یا دیکد لینک {link}: {e}")
        return ""

def main():
    print("🛠️ ترکیب‌کننده‌ی چند سابسکریپشن Xray/V2Ray\n")
    links = get_links()
    if not links:
        print("⛔ هیچ لینکی وارد نشد. خروج.")
        return

    all_configs = []
    for link in links:
        print(f"⬇️ در حال دریافت: {link}")
        content = fetch_and_decode(link)
        if content:
            all_configs.append(content)

    if not all_configs:
        print("⚠️ هیچ کانفیگی دریافت نشد.")
        return

    combined = "\n".join(all_configs)
    encoded = base64.b64encode(combined.encode()).decode()

    output_path = "/var/www/sub/merged"
    with open(output_path, "w") as f:
        f.write(encoded)

    import socket
    ip = socket.gethostbyname(socket.gethostname())
    print(f"\n✅ فایل ترکیبی ساخته شد و در مسیر Nginx قرار گرفت.")
    print(f"📎 لینک نهایی سابسکریپشن:\nhttp://{ip}:2096/sub/merged")

if __name__ == "__main__":
    main()
EOF

echo "⚙️ کانفیگ nginx برای سابسکریپشن..."

cat > /etc/nginx/sites-available/sub-merger << 'EOF'
server {
    listen 2096 default_server;
    server_name _;

    location /sub/ {
        alias /var/www/sub/;
        autoindex off;
        add_header Access-Control-Allow-Origin *;
        add_header Content-Type text/plain;
    }
}
EOF

ln -sf /etc/nginx/sites-available/sub-merger /etc/nginx/sites-enabled/sub-merger
nginx -t && systemctl restart nginx

echo "🚀 اجرای اسکریپت ترکیب‌کننده..."
python3 combine.py
