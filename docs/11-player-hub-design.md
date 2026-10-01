# P4 Player Hub — design handoff

วันที่: 2026-09-22 · สถานะ: แบบเสนอเพื่อพัฒนา frontend

เปิด `11-player-hub-preview.html` ใน browser เพื่อดูแบบทั้งสี่มุมมองและลองกรอกรหัสห้อง ข้อมูลทั้งหมดใน preview เป็นข้อมูลตัวอย่าง ไม่เชื่อม API

## ฐานการออกแบบ

อ้างอิง Fantasy Player Hub ใน commits `11ca892` และ `6943d5e` ซึ่งตรงกับคำอธิบาย issues ปัจจุบัน ส่วน working branch ตอนออกแบบยังเป็นหน้า Material รุ่นก่อน จึงต้องนำงานไปต่อบน branch ที่มี Fantasy UI แล้ว หรือรวม baseline นั้นก่อน

- ใช้ `FantasyBackdrop`, `FantasyPanel`, `fantasySurfaceTheme`, `PlayerHubNavigation`, `AppButton`, `AppModal`, `AppTextField`, `SkeletonBox` และ `ErrorView` ที่มีอยู่ใน baseline
- พื้นหลังสนาม `arena_background_blurred.webp` และ texture สีน้ำเงินเดิม ไม่ต้องสร้าง asset ใหม่
- สีหลัก: สนาม `#081522`, แผง `#10283B`, ขอบ `#6FA5C4`, ทอง `#F2C14E`, ตัวอักษร `#FFF5D6`, ข้อความรอง `#B8CEF0` ใช้สีสำเร็จ/ผิดพลาดจาก theme พร้อมข้อความเสมอ
- ใช้ platform font ตาม `AppTypography`; title 22–28, body 14–16, line height ภาษาไทยอย่างน้อย 1.4; สเปก Flutter ใช้ `textTheme` ไม่กำหนดขนาดแยกใน feature
- ระยะขอบมือถือ 16–24, ช่องว่าง 8/16/24, เป้ากดอย่างน้อย 48 dp; หน้าหลักกว้างสูงสุด 640–760 dp ตาม baseline
- ยึดตัวตนผู้เล่นและอันดับเป็นจุดเด่น แสดงข้อมูลเป็นแถวอ่านง่าย ไม่เพิ่ม podium, rank tier, กราฟ หรือระบบ season ที่ API ยังไม่รองรับ

## Profile — #257

ลำดับ: หัวหน้า → บัญชีเดิม (initials, username, email) → rating และ current rank → สถิติ → ประวัติการแข่งขัน → การจัดการบัญชี → navigation เดิม

สถิติใช้แผงเดียว ตาราง 2 × 2: แข่งขัน, ชนะ, แพ้, อัตราชนะ ตัวเลขชิดซ้าย ใช้พื้นที่มากกว่าป้ายกำกับเล็กน้อย ไม่ใช้ progress ring เพราะไม่สื่อข้อมูลเพิ่ม

- Rating มาจากบัญชี; rank และสถิติมาจาก #254
- บัญชีและสถิติมี loading/error แยกกัน โหลดสถิติล้มเหลวต้องยังแก้ชื่อและ logout ได้
- ผู้เล่นใหม่: จำนวนแข่ง/ชนะ/แพ้เป็น 0, win rate เป็น “—”, ข้อความ “ลงสนามครั้งแรกเพื่อเริ่มบันทึกสถิติ”; rank แสดงตาม server ถ้า null ใช้ “ยังไม่มีอันดับ” ไม่อนุมานจากจำนวนแข่ง
- ปุ่ม “ดูประวัติการแข่งขัน” ไป `/history`; กดอันดับไป `/leaderboard`
- คง validation, บันทึกชื่อ และ confirmation logout เดิม
- ไม่คำนวณ losses = matches − wins เพราะระบบมีผลเสมอ; ใช้ค่าที่ backend ส่งมา และให้ #254 ระบุนิยาม winRate/ผลเสมอก่อนเชื่อม

## Private room — #258 / #259

ใช้ปุ่ม Create/Join ใน Lobby เดิม เป็นสองทางเข้าสู่ **หน้ารอเดียวกัน** แสดงตาม owner/member ไม่ต้องทำหน้าสร้างห้องที่มีฟอร์มตั้งชื่อ

Create: กด “สร้างห้อง” → ปุ่มแสดง loading → server ส่งห้อง → แสดงหน้ารอ

Join: กด “เข้าร่วมห้อง” → bottom sheet ช่องรหัสเดียว → trim + uppercase → ตรวจรูปแบบตาม contract → ส่ง join → หน้ารอเดียวกัน → เมื่อ server ส่ง matchId จึงไป `/match/:id`

หน้ารอ (ปรับ 2026-09-23): back/ชื่อหน้า → แถบรหัสห้องขนาดเล็กและคัดลอก → แผง “เตรียมประลอง” ขนาดใหญ่ → คำอธิบายเริ่มอัตโนมัติ → ยกเลิกห้อง (owner) / ออกจากห้อง (member)

แถบรหัสใช้ตัวอักษรประมาณ 20 dp สีข้อความปกติ วางรหัสซ้าย ปุ่มคัดลอกขวา ลด padding เหลือ 12–14 dp และคงเป้ากด 48 dp ให้ผู้เล่นเป็นจุดสนใจหลักแทนรหัส

แผงประลองแสดงผู้เล่นสองฝั่งคั่นด้วย **VS** สีทอง: ฝั่งคุณโทนฟ้า คู่แข่งโทนอิฐหม่น พร้อมป้ายบอกฝั่ง ไม่อาศัยสีอย่างเดียว แต่ละฝั่งเป็นกรอบแนวตั้ง มี initials ขนาดใหญ่ ชื่อ และบทบาท พื้นที่ประลองสูงประมาณ 300 dp แบบยืดได้ ใช้คอลัมน์ `Expanded / VS / Expanded` ชื่อยาว wrap ได้ ช่องคู่แข่งว่างใช้ “?” ขอบประพร้อมคำว่า “รอผู้ท้าชิง”; เมื่อ join แสดง initials/ชื่อจริงและขอบทึบ ไม่ใช้ภาพยูนิตแทนผู้เล่นเพราะยังไม่มีระบบเลือกตัวละคร เมื่อ text scale สูงให้ขยายความสูงตามเนื้อหา

- ไม่เพิ่มปุ่ม Ready/Start เพราะ #255 ระบุว่าเริ่มเมื่อครบสองคน
- รหัสตัวอย่างในแบบคือ `K7M2Q9`; **จำนวนตัวอักษร/ชุดอักขระยังเป็นข้อเสนอ** ต้องยืนยันจาก #255 ก่อนเขียน validation จริง ใช้ช่องเดียวรองรับ paste แทนช่อง OTP แยก
- ไม่เปิดช่องให้แก้จำนวนผู้เล่น แผนที่ หรือกติกา; ระบบนี้รองรับสองคน
- “คัดลอกแล้ว” แสดงเมื่อ clipboard สำเร็จเท่านั้น; ถ้าล้มเหลวให้เลือกรหัสคัดลอกเอง
- การสร้าง/เข้าร่วมระหว่าง matchmaking ต้องถูกปิดพร้อมคำอธิบาย “ยกเลิกการค้นหาคู่ก่อน”; ไม่สร้างห้องหรือ join ซ้ำระหว่างรอ ACK
- เมื่อ offline ปิด mutation; reconnect คงห้องที่เห็นพร้อม banner แล้ว sync server state ก่อนเปิดปุ่มอีกครั้ง ห้ามออกหรือสร้างห้องใหม่โดยอัตโนมัติ
- กด back ตอนอยู่ห้องต้องยืนยันการออก; ข้อความ owner แจ้งว่าจะปิดห้อง จากนั้นส่ง leave/cancel และกลับ Lobby เมื่อ server ยืนยัน
- แสดง expiresAt เป็น “ใช้ได้ถึง …” เมื่อ contract รองรับ ไม่สร้าง countdown/TTL เอง
- ครบสองคนแสดง “กำลังเข้าสู่สนาม…” ชั่วคราว; ใช้ matchId จาก server และป้องกัน navigation ซ้ำ ห้ามแสดง waiting ค้างเพื่อรอให้ผู้ใช้กด Start
- เสนอ route `/room` สำหรับ active room ที่ผูกกับ session; ยังไม่ถือเป็น API contract และไม่ต้องใช้รหัสเชิญใน URL

| สถานะผิดพลาด | ข้อความ / การแก้ไข |
|---|---|
| invalid | รหัสห้องไม่ถูกต้อง ตรวจสอบแล้วลองอีกครั้ง |
| not-found | ไม่พบห้องนี้ ตรวจสอบรหัสกับเพื่อน |
| full | ห้องนี้มีผู้เล่นครบแล้ว ขอรหัสห้องใหม่ |
| expired | รหัสห้องหมดอายุแล้ว ให้เจ้าของสร้างห้องใหม่ |
| already-in-room | คุณอยู่ในห้องแล้ว; เปิดห้องปัจจุบันหลัง sync server |
| disconnected | การเชื่อมต่อขาดหาย กำลังเชื่อมต่อใหม่ |
| request timeout | ยังยืนยันผลไม่ได้ ลองเชื่อมต่ออีกครั้ง; sync ก่อน retry mutation |

## Leaderboard — #256

เข้าจาก Lobby “ดูทั้งหมด” หรืออันดับใน Profile; route `/leaderboard` พร้อม back กลับต้นทาง เป็นหน้ารอง ไม่เพิ่มแท็บหลักที่ห้า

- หัวหน้า “ตารางอันดับ” + “เรียงตามเรตติ้ง” ใช้แทน “อันดับประจำฤดูกาล” จน backend มี season จริง
- แผงอันดับของฉันอยู่เหนือรายการ แสดง rank, username, rating แม้ตัวเองอยู่นอกหน้าแรก
- ตารางใช้ 3 คอลัมน์: อันดับ / ผู้เล่น / เรตติ้ง; highlight ตัวเองด้วยพื้นอ่อนและคำว่า “คุณ” อันดับ 1–3 เน้นเลขสีทองโดยไม่เพิ่มความสูงแถว
- ใช้ rank ตาม backend รวม tie ordering ห้ามคำนวณจาก index ของหน้าปัจจุบัน
- Pagination ใช้ “โหลดเพิ่มเติม” ท้ายรายการ; โหลด/ผิดพลาดหน้าถัดไปต้องเก็บแถวเดิมไว้พร้อม retry
- Lobby preview ใช้ 3 อันดับแรก + อันดับตัวเอง ถ้าอยู่ใน 3 อันดับแล้วไม่ต้องทำแถวซ้ำ
- แยก error ของ own-rank กับรายการ ถ้า own-rank ไม่มีข้อมูลใช้ “ยังไม่มีอันดับ” ไม่ซ่อน leaderboard
- Empty: “ยังไม่มีข้อมูลอันดับ” พร้อมกลับ Lobby; initial loading ใช้ skeleton; error ใช้ retry ในแผง
- ไม่มีค้นหา filter ประเทศ/เพื่อน หรือ rewards ในรอบนี้ เพราะไม่อยู่ใน #254

## Responsive และ accessibility

- 360 dp: layout คอลัมน์เดียว สถิติ 2 × 2; ข้อความชื่อยาวตัดได้แต่เปิดอ่านเต็มผ่าน semantics/tooltip ส่วน email wrap ได้
- Text scale 2×: สถิติปรับคอลัมน์ตามพื้นที่ ปุ่มยอมสูงขึ้น รายการยอม wrap; ไม่ล็อกความสูงเนื้อหา
- Keyboard: Join sheet เลื่อนขึ้นตาม viewInsets และ scroll ได้ ปุ่มส่งยังเข้าถึงได้; Enter ส่งเมื่อ valid และไม่ loading
- แท็บเล็ต: จำกัดความกว้างเนื้อหา ไม่ยืดตัวเลขและแถวทั่วจอ
- เพิ่ม SafeArea ให้ action ท้ายหน้ารอและ navigation; ข้อความบน texture ใช้แผงทึบเพียงพอ
- สีไม่ใช่สัญญาณเดียว: ระบุ “คุณ”, “เจ้าของห้อง”, “รอผู้เล่น”; focus ชัดเจน, ข้อผิดพลาดประกาศผ่าน live region
- ไม่เพิ่ม animation ต่อเนื่อง; loading และ room status ต้องอ่านได้เมื่อ reduced motion เปิด

## ขนาดงานและ handoff

UI หลักเพิ่ม 2 หน้า (Leaderboard, Room waiting), 1 Join sheet, ต่อเติม Profile และ Lobby เดิม Component ใหม่ที่คุ้มใช้ซ้ำ: `PlayerStatsPanel`, `LeaderboardRow`, `RoomMemberRow` ส่วน code input ไม่ต้องทำ abstraction จนมีผู้ใช้ซ้ำ

ทำ UI ด้วย fixture แยกจาก production provider ได้ก่อน จากนั้นเชื่อม #254 (statistics/leaderboard) และ #255 (room state) เมื่อ contract ชัดเจน งาน frontend ที่กินเวลามากสุดคือ reconnect, timeout และการออกจากห้องระหว่าง match เริ่ม ไม่ใช่การวาง layout

ลำดับแนะนำ: Profile stats → Leaderboard + Lobby preview → Join sheet + shared room screen → API/WS integration

เกณฑ์ตรวจ: 360 dp และ tablet ไม่มี overflow, ชื่อยาว/ข้อความ 2× อ่านได้, account ใช้งานได้เมื่อ stats ล้มเหลว, pagination retry ไม่ล้างรายการ, join ซ้ำถูกป้องกัน, offline/expiry/leave/reconnect ถูกแสดงครบ, ทั้งสองฝ่ายเข้า matchId เดียวกันจาก server

แหล่งข้อกำหนด: [#254](https://github.com/JaJoJi/mobile-final-project/issues/254), [#255](https://github.com/JaJoJi/mobile-final-project/issues/255), [#256](https://github.com/JaJoJi/mobile-final-project/issues/256), [#257](https://github.com/JaJoJi/mobile-final-project/issues/257), [#258](https://github.com/JaJoJi/mobile-final-project/issues/258), [#259](https://github.com/JaJoJi/mobile-final-project/issues/259)
