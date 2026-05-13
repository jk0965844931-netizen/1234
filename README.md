# Local Voice PiP Translator

แอพ iPhone ตัวอย่างสำหรับแปลเสียงแบบภายในเครื่องและแสดงคำแปลในหน้าต่าง Picture in Picture (PiP) คล้ายแนวทางของแอพแปลสด เช่น Viitor

## ความสามารถหลัก

- ฟังเสียงจากไมโครโฟนด้วย `Speech` framework
- บังคับใช้ on-device speech recognition (`requiresOnDeviceRecognition = true`) เพื่อไม่ส่งเสียงออกนอกเครื่อง
- แปลข้อความด้วย `Translation` framework ของ Apple เมื่ออุปกรณ์และแพ็กภาษาในเครื่องรองรับ
- แสดงผลคำแปลใน UI หลักและเรนเดอร์ข้อความเป็นวิดีโอสำหรับ Picture in Picture
- มี GitHub Actions workflow สำหรับ build บน macOS runner และอัปโหลดไฟล์ `.ipa`
- repository นี้ตั้งใจเก็บเฉพาะไฟล์ text/source เท่านั้น จึงไม่ commit ไฟล์ไบนารี เช่น PNG/PDF

## ข้อจำกัดสำคัญของ iOS

PiP ของ iOS ไม่ได้เปิดให้แสดง SwiftUI view ลอยได้โดยตรง แอพนี้จึงใช้ `AVSampleBufferDisplayLayer` เพื่อเรนเดอร์คำแปลเป็นเฟรมวิดีโอ แล้วส่งให้ `AVPictureInPictureController`

ไฟล์ IPA ที่ workflow สร้างแบบไม่ signing (`LocalVoicePiPTranslator-unsigned.ipa`) ใช้สำหรับตรวจ artifact/build output เท่านั้น หากต้องติดตั้งบน iPhone จริง ต้องใช้ Apple Developer certificate และ provisioning profile

## Build IPA บน GitHub

1. Push repository นี้ขึ้น GitHub
2. เปิดแท็บ **Actions**
3. เลือก workflow **Build iPhone IPA**
4. กด **Run workflow**
5. ดาวน์โหลด artifact ชื่อ `LocalVoicePiPTranslator-ipa`

### สร้าง IPA สำหรับติดตั้งบนเครื่องจริง

เพิ่ม GitHub repository secrets ต่อไปนี้ก่อนรัน workflow:

- `IOS_CERTIFICATE_P12_BASE64` — ไฟล์ `.p12` ที่ encode เป็น base64
- `IOS_CERTIFICATE_PASSWORD` — รหัสผ่านของ `.p12`
- `IOS_PROVISIONING_PROFILE_BASE64` — provisioning profile ที่ encode เป็น base64
- `IOS_TEAM_ID` — Apple Developer Team ID
- `IOS_EXPORT_METHOD` — ค่า export method เช่น `ad-hoc`, `development`, หรือ `app-store` (ไม่ใส่จะใช้ `ad-hoc`)

ตัวอย่าง encode ไฟล์บน macOS:

```bash
base64 -i certificate.p12 | pbcopy
base64 -i profile.mobileprovision | pbcopy
```

## Build ในเครื่องด้วย Xcode

```bash
xcodebuild \
  -project LocalVoicePiPTranslator.xcodeproj \
  -scheme LocalVoicePiPTranslator \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  build
```

## การใช้งานบน iPhone

1. เปิดแอพและอนุญาต Microphone + Speech Recognition
2. เลือกภาษาต้นทางและปลายทาง
3. กด **เริ่ม** เพื่อฟังเสียง
4. กด **เปิด PiP** เพื่อแสดงคำแปลแบบหน้าต่างลอย

> หมายเหตุ: อุปกรณ์ต้องมี iOS 18 ขึ้นไปและ language packs ที่รองรับ Translation framework หากยังไม่ได้ติดตั้งภาษา ระบบอาจขอให้ดาวน์โหลดแพ็กภาษา และการแปลจะทำงานภายในเครื่องเมื่อแพ็กภาษาพร้อมใช้งาน
