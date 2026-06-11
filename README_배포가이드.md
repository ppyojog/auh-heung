# 🐯 Project AuhHeung — 링크 하나로 공유하기 (GitHub Pages 자동배포)

받는 사람은 **링크만 클릭하면** 브라우저(PC·모바일)에서 바로 플레이합니다.
대장님 컴퓨터에 Flutter를 깔 필요가 없습니다 — GitHub가 클라우드에서 알아서 빌드합니다.

준비물: **GitHub 계정**(무료) 하나. (github.com 가입)

---

## 0단계. 게임 코드 넣기 (딱 한 번, 제일 중요)

`web_deploy/lib/main.dart` 는 지금 **빈 껍데기**입니다. 여기에 진짜 게임 코드를 넣어야 합니다.

1. 상위 폴더의 **`AuhHeung_DartPad_MMO_v8.dart`** 파일을 메모장/에디터로 엽니다.
2. **전체 선택(Ctrl+A) → 복사(Ctrl+C)**.
3. `web_deploy/lib/main.dart` 를 열어 **내용을 전부 지우고 붙여넣기(Ctrl+V) → 저장**.

> 팁: 그냥 `AuhHeung_DartPad_MMO_v8.dart` 를 복사해서 `web_deploy/lib/` 안에 두고
> 파일 이름을 `main.dart` 로 바꿔도 됩니다(기존 main.dart는 덮어쓰기).

---

## 1단계. GitHub 저장소 만들기

1. **https://github.com** 로그인 → 우측 상단 **`+` → New repository**.
2. Repository name: 예) **`auh-heung`** (영문/소문자/하이픈 권장).
3. **Public** 선택 (Pages 무료 배포는 Public이 가장 쉬움).
4. **Create repository** 클릭.

---

## 2단계. 파일 업로드

생성된 저장소 페이지에서 **`Add file` → `Upload files`** 클릭.

- `web_deploy` 폴더 **안의 내용물 전부**(lib, web, pubspec.yaml, .github 폴더까지)를
  드래그해서 올립니다. (`web_deploy` 폴더 자체가 아니라 그 **안의 것들**을 올려야
  `pubspec.yaml` 이 저장소 최상단에 오게 됩니다)
- ⚠️ `.github/workflows/deploy.yml` 경로가 그대로 유지돼야 자동배포가 작동합니다.
  폴더째 드래그하면 경로가 보존됩니다.
- 맨 아래 **Commit changes** 클릭.

> 폴더 구조가 이렇게 되면 정상입니다:
> ```
> (저장소 최상단)
>  ├── pubspec.yaml
>  ├── lib/main.dart
>  ├── web/index.html
>  └── .github/workflows/deploy.yml
> ```

---

## 3단계. Pages 자동배포 켜기

1. 저장소 상단 **Settings → 좌측 Pages**.
2. **Source** 를 **`GitHub Actions`** 로 선택. (저장 자동)

---

## 4단계. 배포 기다리기 → 링크 받기

1. 저장소 상단 **Actions** 탭으로 가면 "Deploy AuhHeung..." 작업이 돌고 있습니다.
2. 초록 체크(✓)가 뜰 때까지 **2~4분** 기다립니다. (Flutter 빌드 시간)
3. 끝나면 **Settings → Pages** 상단에 링크가 뜹니다:
   ```
   https://<내아이디>.github.io/auh-heung/
   ```
4. **이 링크를 누구에게 보내든, 클릭하면 바로 플레이됩니다.** 🎉

---

## 업데이트하는 법

게임을 고친 뒤 `lib/main.dart` 만 다시 업로드(덮어쓰기)하면,
Actions가 자동으로 다시 빌드·배포합니다. 링크는 그대로입니다.

---

## (대안) 더 빠른 1회성 공유 — Netlify Drop
로컬에 Flutter가 설치돼 있다면:
1. 터미널에서 `flutter build web --release`
2. 생성된 **`build/web`** 폴더를 **https://app.netlify.com/drop** 에 드래그
3. 즉시 임시 URL 발급 (가입하면 영구 링크).

---

문제가 생기면 Actions 탭의 빨간 로그를 캡처해서 보내주세요. 어흥!!
