# Room design versions

## V2 ครบทุกหน้า (อัปเดตตามคำขอผู้ใช้)

เปิด `13-player-hub-v2.html` เป็นจุดเริ่มต้น เลือก Profile / Create room / Join room / Leaderboard จากปุ่มด้านบน เก็บ V1 และแบบห้อง V2 เดิมทั้งหมด

**แบบที่เลือกสำหรับพัฒนาต่อ: V2** (ยืนยัน 2026-09-23) ใช้ `13-player-hub-v2.html` เป็น visual baseline ของงาน P4-FE-04 ถึง P4-FE-07 ส่วน V1 เป็นแบบสำรองสำหรับอ้างอิงเท่านั้น

- Profile: ตราผู้เล่น + rating, แถบสถิติแบบ HUD, อันดับ, ลิงก์ประวัติ และแก้ชื่อผ่าน dialog ตัวอย่าง
- Create room: แสดง `12-room-v2.html` ใน iframe ใช้สนาม VS เดิมพร้อมปุ่มจำลองสถานะ
- Join: หน้ารหัสห้องพร้อมภาพประกอบจาก asset เดิม ลอง K7M2Q9 เพื่อเปิดหน้าห้อง (preview ห้องยังแสดงบทบาท owner ไม่จำลอง member lifecycle)
- Leaderboard: เน้นผู้เล่นอันดับหนึ่ง ตารางรายการและอันดับตัวเองแยกไว้ พร้อมโหลดเพิ่ม
- Profile/Leaderboard มีตัวเลือกตัวอย่าง loading/empty/error/success สำหรับส่วนข้อมูล; ข้อมูลบัญชี/อันดับตนเองเป็น fixture แยก ไม่ใช่การเชื่อม server

ตรวจ syntax JavaScript, ID ซ้ำ, หน้าครบ และไฟล์อ้างอิงแล้ว ยังไม่ได้ตรวจภาพผ่าน browser จริง

- **V1 (เก็บไว้):** `11-player-hub-preview.html` พร้อม handoff `11-player-hub-design.md` — แบบการ์ดสองฝั่งและ VS ที่ผู้ใช้ชอบ เก็บไฟล์เดิมไว้ไม่แก้ทับ
- **V2 (2026-09-23):** `12-room-v2.html` — Arena lobby ใช้ฉากสนามเต็มพื้นที่ ตราผู้เล่นสองฝั่ง แถบชื่อเฉียง ข้อมูลห้องเป็น toolbar และสถานะการเชื่อมต่อบนหัวหน้า Responsive เป็นสองฝั่งทั้งมือถือและจอกว้าง

V2 เปลี่ยนเฉพาะหน้าสร้าง/รอห้อง มีสถานะรอเพื่อน, เพื่อนเข้าร่วม และ reconnect ให้กดเปรียบเทียบ ข้อมูลทั้งหมดเป็น fixture ไม่ได้เชื่อม backend รหัส/จำนวนสมาชิก/สถานะจริงต้องใช้ #255 เช่นเดิม เริ่มอัตโนมัติ ไม่มีการเลือกตัวละคร ไม่มีระบบ Ready ใหม่ ไม่แสดง ping หรือ rank ที่ room contract ยังไม่ได้ระบุ

ตรา initials สร้างจากรูปทรง CSS ในแบบ สำหรับ Flutter ใช้ CustomClipper/CustomPainter หรือรูปทรงง่ายที่ใกล้เคียง ไม่ต้องสร้างภาพต่อผู้เล่น ฉากเดิม `arena_background_landscape.webp` เปลี่ยนเป็น portrait asset ใน Flutter บนจอตั้งตามความเหมาะสม ข้อความแยกจากภาพทั้งหมด

## Research และข้อจำกัด

ผู้ใช้เสนอ https://www.gameuidatabase.com/ แต่เครื่องมือเว็บถูก robots.txt ปฏิเสธ และไม่มี Firecrawl CLI ติดตั้ง จึงไม่อ้างว่าได้ตรวจภาพจากฐานข้อมูลนั้น

แหล่งที่ค้นพบ: [Street Fighter 6 official manual — Online / Custom Room](https://game.capcom.com/manual/SF6/en/ps5/page/6/6) และ [Street Fighter 6 showcase โดย Capcom บน PlayStation Blog](https://blog.playstation.com/2023/04/20/street-fighter-6-showcase-new-gameplay-details-future-fighters-revealed-and-demo-launched/) รองรับแนวคิด private online room แยกจาก social hub การจัดสองฝั่ง, VS, crest และ nameplate เป็นข้อเสนอการออกแบบของเรา ไม่ใช่รายละเอียดที่อ้างว่าคัดจากภาพเกมเหล่านี้

ทิศทางจาก frontend-design: เก็บตัวตน fantasy ของโปรเจกต์โดยใช้ asset เดิม ให้สนามและผู้เล่นเป็นจุดเด่น ลดกล่องข้อมูลซ้อนกัน รหัสห้องเป็น utility แทน hero ของหน้า
