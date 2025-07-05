#!/bin/bash

# --- اسکریپت نصب و اجرای تعاملی از گیت‌هاب ---

# توابع و متغیرها
# --------------------------------------------------
# رنگ‌ها برای خروجی بهتر
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# تابع نمایش پیام
function print_message() {
    echo -e "${GREEN}---> $1${NC}"
}

# تابع نمایش پیام مهم
function print_important() {
    echo -e "${YELLOW}*** $1 ***${NC}"
}

# بخش اصلی اسکریپت
# --------------------------------------------------

# ۱. نصب پیش‌نیازها
print_message "Updating package lists and installing prerequisites (python3, pip, curl)..."
sudo apt-get update > /dev/null 2>&1
sudo apt-get install -y python3 python3-pip curl > /dev/null 2>&1
print_message "Installing required Python libraries (Flask, Requests)..."
pip3 install flask requests > /dev/null 2>&1

# ۲. دریافت لینک‌های سابسکریپشن از کاربر
print_message "Please enter your subscription links."
print_important "Enter one link per line. Press ENTER on an empty line to finish."

links=()
while true; do
    read -p "Subscription Link: " link
    if [ -z "$link" ]; then
        break
    fi
    links+=("\"$link\"")
done

# تبدیل آرایه bash به لیست پایتون
IFS=,
python_links="${links[*]}"

if [ -z "$python_links" ]; then
    echo -e "${RED}Error: No subscription links were entered. Aborting.${NC}"
    exit 1
fi


# ۳. ساخت فایل پایتون در سرور
print_message "Generating the Python application file (app.py)..."
cat <<EOF > app.py
import requests
from flask import Flask, Response
import base64

app = Flask(__name__)

SUBSCRIPTION_LINKS = [$python_links]
PORT = 8080

def fetch_and_decode_configs(url):
    try:
        headers = {'User-Agent': 'Mozilla/5.0'}
        response = requests.get(url, timeout=10, headers=headers)
        response.raise_for_status()
        return base64.b64decode(response.content).decode('utf-8').strip().split('\n')
    except Exception:
        return []

@app.route('/sub')
def combined_subscription():
    all_configs = []
    for link in SUBSCRIPTION_LINKS:
        all_configs.extend(fetch_and_decode_configs(link))
    
    combined_content = "\n".join(all_configs)
    return Response(base64.b64encode(combined_content.encode('utf-8')), mimetype='text/plain')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT)
EOF

# ۴. اجرای برنامه در پس‌زمینه
print_message "Starting the subscription service in the background..."
# اجرای برنامه با nohup تا بعد از بستن ترمینال هم فعال بماند
nohup python3 app.py > /dev/null 2>&1 &

# ۵. پیدا کردن IP سرور و نمایش لینک نهایی
SERVER_IP=$(curl -s ifconfig.me)
print_message "Setup is complete!"
echo "------------------------------------------------------------------"
print_important "Your new combined subscription link is ready:"
echo -e "${CYAN}http://$SERVER_IP:8080/sub${NC}"
echo "------------------------------------------------------------------"
echo "The service is running in the background. You can now close this terminal."
