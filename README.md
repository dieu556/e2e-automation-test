# baresip + Twilio Elastic SIP Trunk

Container [baresip](https://github.com/baresip/baresip) (`ghcr.io/baresip/docker/baresip`) gọi ra PSTN qua **Termination** của Twilio Elastic SIP Trunk. Trunk này không cần `REGISTER`.

Baresip gửi INVITE tới edge (`pstn.singapore.twilio.com` mặc định), Request-URI vẫn là termination URI của trunk. `From` là caller ID. Digest username/password là Credential List, tách khỏi số gọi đi.

Âm thanh phía mình là tiếng sine 440 Hz (`ausine`). Phía nghe remote bị bỏ (`aubridge`). Đủ để kiểm tra signaling và RTP đi ra.

## Việc cần có trên Twilio

1. Elastic SIP Trunking → tạo trunk.
2. **Termination**: đặt URI, ví dụ `your-trunk.pstn.twilio.com`.
3. **Credential List** (nên dùng cho máy ở nhà, IP động). Gắn list đó vào trunk.
   Nếu vừa gắn ACL vừa gắn credential thì Twilio bắt **cả hai**. ACL phải chứa IP public hiện tại, nếu không INVITE bị từ chối trước khi tới bước password.
4. **Caller ID** là một Twilio number trên account, hoặc Verified Caller ID. Trial chỉ gọi được số đã verify.
5. Codec PSTN của trunk là PCMU/PCMA. Project chỉ mời hai codec này.

## Chạy cuộc gọi thử

```bash
cp .env.example .env
# dien TWILIO_TERMINATION_URI, username, password, TWILIO_CALLER_ID, DESTINATION

chmod +x scripts/call.sh docker/entrypoint.sh
./scripts/call.sh +84901234567
```

Số trên dòng lệnh ghi đè `DESTINATION` trong `.env`. Tham số thứ hai là số giây trước khi cúp:

```bash
./scripts/call.sh +84901234567 15
```

Script bật container, gửi lệnh `dial` qua cổng điều khiển `127.0.0.1:4444`, giữ máy, gửi `hangup`, rồi tắt container. Log SIP in ở cuối.

## Gọi tay trong CLI

```bash
docker compose run --rm -it --service-ports baresip
```

Trong prompt baresip:

```text
/dial sip:+84901234567@your-trunk.pstn.twilio.com;transport=tcp
/hangup
/quit
```

Đổi host và `transport` cho khớp `.env`.

## Đọc kết quả

| Log | Ý nghĩa |
| --- | --- |
| `407` rồi gọi tiếp | Twilio đòi digest, baresip gửi lại credential |
| `403` / `603` | Sai password, sai ACL, hoặc caller ID không được phép |
| `CALL_RINGING` | Đã đổ chuông |
| `CALL_ESTABLISHED` | Máy bắt. Đầu kia nghe tiếng bíp 440 Hz nếu RTP đi được |
| `CALL_CLOSED` ngay sau INVITE | Đọc dòng `param` / SIP reason trong log |

Audio hai chiều trên Docker Desktop (macOS) thường không ổn: SDP cần IP public, còn RTP quay lại phải xuyên NAT của máy ảo Docker. Signaling (đổ chuông, bắt máy) vẫn là dấu hiệu trunk đã thông. Muốn tiếng ổn định, chạy cùng compose này trên một Linux host có IP public, hoặc `network_mode: host`.
