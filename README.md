# MoonVFXCompiler (HamVFX)

Plugin สำหรับ Roblox Studio ที่ผมพัฒนาขึ้นเพื่อลดเวลาการพอร์ต Cutscene และ VFX เข้าเกม
อ่านไฟล์เซฟของ **Moon Animator 2** หรือโปรเจกต์ของ **Eclipse Animator** แล้วแปลงเป็น Script ที่พร้อมใช้งานในเกมได้ภายในปุ่มเดียว

> เวอร์ชันล่าสุด: **v3.4.0** — รองรับ Eclipse Animator แล้ว + มี Plugin แปลงเซฟ Moon → Eclipse (ดูด้านล่าง)

---

## ปัญหา

งานหลักของผมในฝั่ง Front-end คือการนำเอฟเฟกต์ที่ทีมเตรียมไว้มาพอร์ตลงในตัวเกม ส่วนใหญ่จะเป็นพวก Cutscene
ซึ่งเอฟเฟกต์จะทำงานปกติใน Preview ของ Moon Animator 2 แต่ยังใช้ในเกมจริงไม่ได้ ปัญหาที่ผมเจอคือ

- ต้องเขียน Script รันเอฟเฟกต์ให้ตรงกับจังหวะทีละเฟรมด้วยมือ
- ต้องเปิด Roblox Studio หลายหน้าต่างพร้อมกัน เพื่อดู Preview และเช็คจังหวะไปพร้อมกัน
- ใช้เวลาเฉลี่ยประมาณ **4–6 ชั่วโมง** ต่อเอฟเฟกต์ความยาว 30 วินาที – 1 นาที

## วิธีแก้

ผมจึงพัฒนา Plugin สำหรับ Roblox Studio ที่ใช้ร่วมกับ Moon Animator 2 (Plugin ยอดนิยมสำหรับทำ Animation)
และตอนนี้รองรับ Eclipse Animator ด้วย

VFXCompiler จะอ่านไฟล์เซฟของ Animator แล้วแปลงออกมาเป็น Model + ModuleScript `VFXPlayer` ที่พร้อมใช้งาน **ภายในปุ่มเดียว**

## การทำงาน

1. **อ่านไฟล์เซฟ** — ดึงข้อมูลจากไฟล์เซฟของ Moon Animator 2 (หรือโปรเจกต์ Eclipse) ว่าในแต่ละ Keyframe
   มี Object และ Event อะไรบ้าง อยู่ที่เวลาไหน และเปลี่ยน Properties อะไรบ้าง พร้อม Easing ของแต่ละช่วง
2. **เก็บเฉพาะสิ่งที่ถูกแอนิเมตจริง** — แปลงเฟรมเป็นวินาที (`frame / FPS`) เก็บเฉพาะ Property ที่มี Keyframe
   ลงใน Table ข้อมูลจึงเล็กและไม่ซ้ำซ้อน และทำให้ CFrame อ้างอิงจาก RootPart ของตัวละคร (เล่นตามตัวผู้เล่นได้)
3. **จัดเรียง Timeline** — เรียง Event ตามเวลาที่เซฟไว้ เช่น "ณ เวลา X มีการ Emit ของ Particle"
   แล้วแปลงเป็น `task.delay(เวลา, function() ... end)` (โค้ดใน Event ที่อ้าง `workspace.` จะถูกเปลี่ยนไปชี้ที่ Model ที่ Clone ออกมา)
4. **สร้าง VFXPlayer** — นำ Timeline ของแต่ละ Property ใส่ในฟังก์ชัน
   `playKeyframes(Object, Property, PropertyType, TimelineTable)` แล้วรวมเป็น Module `VFXPlayer`
5. **รวม Object ทั้งหมดไว้ใน Group เดียว** — Clone ทุก Object ที่ Script ต้องใช้ (Part, Beam, ParticleEmitter, Rig, CameraRig ฯลฯ)
   มาไว้ใน Model `<ชื่อเซฟ>_VFX` พร้อมใช้งานทันที

## รองรับอะไรบ้าง

- BasePart, Beam, ParticleEmitter, Trail, Light และ Property ทั่วไปที่ Tween ได้
- Lighting / CameraEffect (ColorCorrection, Atmosphere ฯลฯ) — คืนค่าเดิมให้อัตโนมัติเมื่อเอฟเฟกต์จบ
- กล้อง: FieldOfView และ Cutscene ผ่าน CameraRig (กล้องจะตาม `CamPart`)
- Rig ตัวละคร (Humanoid / AnimationController) — ใส่ Animation ID แล้วเล่นอัตโนมัติ
- Vignette / Screen Cover UI
- โค้ดใน Event ของ Moon (`codeBegin` / `codeEnd`) และ Eclipse (`CodeBegin` / `CodeEnd`, Emit ของ VFX, เสียง)
- โหมด **No Cutscene** สำหรับเอฟเฟกต์ที่เล่นในโลกอย่างเดียว (ไม่ยุ่งกับกล้อง / Lighting / UI)

---

## ใหม่ใน v3.4.0: Eclipse Animator

**1. VFXCompiler อ่านโปรเจกต์ Eclipse ได้แล้ว**
เลือกโฟลเดอร์โปรเจกต์ใน `ServerStorage › Eclipse Animator Saves › EclipseAnimator_Saves` (หรืออะไรก็ได้ที่อยู่ข้างใน) แล้วกด Generate VFX เหมือนเดิม
ผลลัพธ์จากโปรเจกต์ Eclipse ที่แปลงมาจากเซฟ Moon ได้ `VFXPlayer` ตรงกับของ Moon ทุกบรรทัด

- กล้องของ Eclipse เป็น Rig อยู่แล้ว จึงใช้เป็น CameraRig ได้ทันที (เปิดโปรเจกต์ใน Eclipse หนึ่งครั้งเพื่อให้ Eclipse สร้างกล้อง แล้ว Export / Upload Animation ของกล้องเหมือน CameraRig ของ Moon)
- Event แบบ Emit และเสียงของ Eclipse จะถูกแปลงเป็นโค้ดใน Timeline

**2. Plugin ใหม่: Moon → Eclipse (`MoonToEclipse.rbxmx`)**
Eclipse เปิดเซฟของ Moon Animator 2 ไม่ได้ Plugin นี้จึงแปลงเซฟ Moon ให้เป็นโปรเจกต์ Eclipse โดยตรง:

- ข้อต่อของ Rig ทุก Keyframe (ท่าทางตรงกับ Moon ทุกเฟรม) พร้อม Easing ครบ (รวมค่า Back / Elastic)
- Property ของ Part / Model / Lighting / Effect, กล้อง (CFrame + FOV)
- Marker / Event พร้อมโค้ด `codeBegin` / `codeEnd`, เสียง และ Action Track (เช่น Emit)
- ไม่แก้ไขเซฟ Moon เดิม และ Undo ได้ (Ctrl+Z)

ข้อจำกัด: Object ที่อยู่ใน CoreGui (เช่น Vignette แบบเก่า) จะถูกข้ามเพราะไม่ถูกเซฟกับ Place,
และ Object สองตัวที่ชื่อซ้ำกันจะใส่ในโปรเจกต์เดียวกันไม่ได้ (Eclipse บังคับให้ชื่อไม่ซ้ำ) — Plugin จะแจ้งเตือนใน Output

---

## การติดตั้ง

1. ดาวน์โหลด `VFXComplier.rbxmx` (และ `MoonToEclipse.rbxmx` ถ้าต้องการตัวแปลง)
2. วางไฟล์ไว้ในโฟลเดอร์ Plugins ของ Roblox Studio
   - Windows: `%LOCALAPPDATA%\Roblox\Plugins`
   - macOS: `~/Documents/Roblox/Plugins`
   (หรือใน Studio: แท็บ Plugins › Plugins Folder)
3. ปิดแล้วเปิด Roblox Studio ใหม่

## วิธีใช้

1. กด **Settings** แล้วตั้ง Path ของ Module `ForgeVFX` และโฟลเดอร์ที่ใช้เก็บ VFX (ค่าเริ่มต้น `ReplicatedStorage.ForgeVFX` / `ReplicatedStorage.VFX`)
2. กด **Get Module** หนึ่งครั้ง เพื่อติดตั้ง `Payload` (`VFXPayload` + ตัวเรียก `VFX`) ไว้ข้าง ForgeVFX
3. เลือกเซฟ Moon Animator 2 (`ServerStorage.MoonAnimator2Saves`) หรือโปรเจกต์ Eclipse
4. กด **Generate VFX** (หรือ **Generate VFX (No Cutscene)**) จะได้ Model `<ชื่อ>_VFX` ใน Workspace
5. ใส่ Animation ID ของ Rig / CameraRig ใน `module.Animations` ของ `VFXPlayer` แล้วย้าย Model ไปไว้ในโฟลเดอร์ VFX

เรียกใช้ในเกม (ฝั่ง Client):

```lua
local VFX = require(game.ReplicatedStorage.Payload.VFX)

-- VFX.Play(ชื่อหรือ Model, rootPart, offset, lifeTime, config)
VFX.Play("Slash", character.HumanoidRootPart, CFrame.new(), 5, {
	PlayCutscene = true,       -- ค่าเริ่มต้น true
	AutoPlayAnimations = true, -- ค่าเริ่มต้น true
})
```

แปลงเซฟ Moon → Eclipse: แถบเครื่องมือ **Moon to Eclipse › Convert Moon Saves** › เลือกเซฟ › **Convert Selected** / **Convert All**
แล้วเปิดโปรเจกต์ได้ที่ Eclipse › Projects

## โครงสร้างไฟล์

| ไฟล์ | คืออะไร |
|---|---|
| `VFXComplier.rbxmx` | ไฟล์ Plugin VFXCompiler (HamVFX v3.4.0) พร้อมติดตั้ง |
| `VFXComplier/` | Source ของ Plugin (`init.server.luau`) + UI ของ Vignette / Screen Cover |
| `MoonToEclipse.rbxmx` | ไฟล์ Plugin แปลงเซฟ Moon → Eclipse พร้อมติดตั้ง |
| `MoonToEclipse/` | Source ของตัวแปลง |
| `exampleGenerated.lua` | ตัวอย่าง `VFXPlayer` ที่ Generate ออกมา (จากเวอร์ชันก่อน) |

---

### English summary

A one-button Roblox Studio plugin that turns a **Moon Animator 2** save or an **Eclipse Animator** project into a ready-to-use VFX model plus a `VFXPlayer` ModuleScript: property tweens with matching easing, event code scheduled on a timeline, character/camera rigs and cutscene camera, all grouped into one model. Cut porting a 30–60 s cutscene effect from 4–6 hours of hand-timed scripting to one click. v3.4.0 adds Eclipse Animator support and a companion **Moon → Eclipse** converter plugin that rewrites Moon saves as Eclipse projects (joints, properties, camera, easing, events).
