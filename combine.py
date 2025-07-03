import requests
import base64

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

    output_file = "combined_subscription.txt"
    with open(output_file, "w") as f:
        f.write(encoded)

    print(f"\n✅ ترکیب با موفقیت انجام شد.")
    print(f"📄 فایل خروجی: {output_file}")
    print(f"\n📎 لینک ترکیبی (Base64):\n\n{encoded[:100]}... [بقیه در فایل ذخیره شده]")

if __name__ == "__main__":
    main()
