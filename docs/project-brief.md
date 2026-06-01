# VolDeck Project Brief

## ชื่อโปรเจกต์

**VolDeck**

macOS menu bar app สำหรับควบคุมเสียงรายแอปแบบ privacy-first

## เป้าหมายหลัก

VolDeck คือแอป macOS ที่ตั้งใจทำให้ผู้ใช้สามารถควบคุมเสียงของแต่ละแอปแยกจากกันได้ โดยไม่ต้องแลกกับ microphone permission หรือ privacy indicator ที่ทำให้รู้สึกเหมือนมีการดักฟังอยู่ตลอดเวลา

เป้าหมายหลักคือ:

- ปรับ volume แยกตามแอป
- mute เฉพาะแอปได้
- ใช้งานจาก menu bar
- ไม่ต้องใช้ microphone permission
- ไม่ทำให้ macOS แสดง orange mic indicator
- ไม่ทำ tracking, analytics หรือ telemetry
- เริ่มจากใช้งานส่วนตัวก่อน แล้วค่อยต่อยอดเป็น product ได้

## ที่มาของโปรเจกต์

ปัญหาเริ่มจากความต้องการง่ายๆ: อยากปิดเสียงเฉพาะเกม Wuthering Waves ระหว่างโหลด แต่ยังอยากดู YouTube หรือใช้แอปอื่นโดยมีเสียงได้ตามปกติ

หลังจากลองศึกษา Background Music พบว่าแอปสามารถทำ per-app volume ได้จริง แต่ architecture ของ Background Music อาศัย virtual input หรือ virtual microphone เพื่อดึง system audio กลับเข้าแอป ทำให้ macOS แสดงไอคอนไมค์สีส้มตลอดเวลา และถ้าปิด microphone permission แอปก็ใช้งานไม่ได้

VolDeck จึงควรเป็นโปรเจกต์ใหม่แบบ clean-room ที่โฟกัสเฉพาะ output control โดยไม่อ่าน microphone และไม่ใช้ audio input capture

## เหตุผลที่ไม่ fork Background Music ต่อ

Background Music ใช้ architecture โดยประมาณดังนี้:

```text
Apps -> Background Music virtual output -> HAL driver -> virtual input/ring buffer -> BGMApp reads virtual input -> BGMApp writes to real output
```

ผลลัพธ์คือ:

- ต้องขอ microphone permission
- macOS แสดง orange mic indicator
- ปิด permission แล้วใช้งานไม่ได้
- ไม่ตรงกับเป้าหมาย privacy-first ที่ต้องการควบคุมเฉพาะ output

อีกเหตุผลคือ Background Music ใช้ GPL ถ้านำ code ไปต่อยอดและ distribute จะต้องเปิด source ตามเงื่อนไขของ GPL ด้วย ถ้าต้องการทำ product ของตัวเองในอนาคต ควรเขียนใหม่แบบ clean-room โดยใช้ได้เฉพาะเป็น reference ด้าน feature, behavior และ user expectation เท่านั้น ไม่ copy code, assets หรือชื่อ

## Architecture ที่ต้องการ

เป้าหมายคือ output-only pipeline:

```text
Mac apps -> VolDeck virtual output device -> per-app mixer/volume logic -> shared audio buffer/helper -> real output device
```

หลักการสำคัญ:

- สร้าง virtual output device ให้ macOS ส่งเสียงแอปเข้ามา
- ทำ per-app volume/mute ใน output path
- ส่งเสียงต่อไปยัง real output device
- ไม่สร้าง virtual input
- ไม่อ่าน microphone
- ไม่ใช้ audio capture/input API
- UI app เป็น menu bar controller
- helper process ทำ output playback อย่างเดียว

## Privacy และ Security Principles

VolDeck ต้อง:

- ไม่ขอ microphone permission
- ไม่แตะ microphone หรือ input device
- ไม่พยายามซ่อน privacy indicator
- ไม่มี analytics, tracking หรือ telemetry
- ไม่มี external data sending โดย default
- ถ้าจะมี crash report ในอนาคต ต้องเป็น opt-in เท่านั้น
- ทำงานแบบ local-first ทั้งหมด

## MVP Scope

MVP แรกควรมี:

- CoreAudio HAL virtual output device
- audio pass-through ไป real output device
- output-only helper หรือ XPC service
- menu bar app
- list แอปที่กำลังส่งเสียง
- volume slider ต่อแอป
- mute ต่อแอป
- master output selector
- safe install/uninstall
- recovery path ถ้า audio system ค้าง

ยังไม่ทำใน MVP:

- cloud sync
- account/login
- analytics
- EQ/noise reduction
- multi-output routing
- advanced presets
- fancy UI เกินจำเป็น

## Technical Risks

งานนี้ลึกและเสี่ยง เพราะแตะ CoreAudio/HAL โดยตรง ประเด็นที่ต้องระวังคือ:

- audio device อาจค้าง
- coreaudiod อาจต้อง restart
- HAL plugin มีข้อจำกัดเรื่องการเรียก HAL client APIs
- ต้องระวัง latency, sample rate และ buffer underrun
- ต้องจัดการ device switching
- ต้องจัดการ sleep/wake
- ต้องมี fail-safe uninstall
- distribution ต้องใช้ signing และ notarization

## Implementation Plan

### Phase 0: Research / Skeleton

- ศึกษา CoreAudio AudioServerPlugIn / HAL plugin
- ดูตัวอย่าง open-source เฉพาะแนวคิด ไม่ copy code
- สร้าง repo ใหม่ชื่อ VolDeck
- วาง architecture docs

### Phase 1: Minimal Virtual Output

- ทำ virtual output device ให้ macOS เห็น
- ให้แอปสามารถเลือก VolDeck เป็น output ได้
- รับ audio stream ได้แบบ minimal
- ยังไม่ต้องทำ per-app volume

### Phase 2: Output Pass-through

- ส่งเสียงจาก virtual output ไป real output
- ใช้ helper process ถ้าจำเป็น
- หลีกเลี่ยง virtual input/mic ทั้งหมด
- ทดสอบว่าไม่มี orange mic indicator

### Phase 3: App / Client Awareness

- แยก audio client/app ได้
- map client เป็น bundle id/process
- แสดงรายการใน menu bar UI

### Phase 4: Per-app Volume / Mute

- เพิ่ม per-app gain
- เพิ่ม mute
- persist settings ต่อ app
- handle app start/stop

### Phase 5: Product Hardening

- installer/uninstaller
- audio recovery tool
- device switching
- sleep/wake
- crash recovery
- signing/notarization
- privacy docs

## Rough Timeline

- Prototype no-mic audio pipeline: 1-3 สัปดาห์
- Personal-use per-app volume/mute: 1-2 เดือน
- Product-quality app: 2-4 เดือนขึ้นไป
- Commercial-ready: 4-8 เดือนขึ้นไป

## Naming Decision

ชื่อที่เลือก: **VolDeck**

เหตุผล:

- สั้น
- จำง่าย
- ฟังเป็น control surface/tool
- `Vol` สื่อถึง volume
- `Deck` สื่อถึง control deck/mixer deck
- public quick search ยังไม่เจอ exact match ด้าน audio/software/app ที่น่ากังวล
- เจอ `Voldeck` เป็นนามสกุล/ชื่อคน แต่ไม่ใช่แบรนด์เสียง

ข้อควรทำก่อนขายจริง:

- เช็ค domain
- เช็ค USPTO
- เช็ค WIPO
- เช็ค EUIPO
- เช็ค trademark ไทย/DIP
- อาจให้ trademark lawyer ทำ clearance

## One-liner

**VolDeck is a privacy-first macOS per-app volume controller that works without microphone permission or audio-input capture.**
