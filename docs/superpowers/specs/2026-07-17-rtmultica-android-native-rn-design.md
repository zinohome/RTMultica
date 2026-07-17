# RTMultica 原生安卓版方案（基于上游 React Native app）

- 状态：草案，待用户 review
- 日期：2026-07-17
- 相关：上游 issue [multica-ai/multica#3412](https://github.com/multica-ai/multica/issues/3412)（"Add Android Build and Release"，未完成）

## 1. 背景

RTMultica 当前的安卓版是 **Capacitor WebView 套壳**：`capacitor.config.json` 把 `server.url`
指向 `https://mtc.naivehero.top:8443`，APK 内无前端代码，打开即全屏 WebView 加载上游 web 前端。
优点是零维护跟随，缺点是**交互观感不原生**——这正是本方案要解决的诉求。

调研上游后发现关键事实：上游 `apps/mobile` **已经是一个完整的 Expo + React Native 原生 app**
（expo-router 原生导航、gesture-handler、reanimated、expo-haptics、nativewind），业务逻辑与
web/desktop 共享 `@multica/core`。它**目前只配置了 iOS**：

- `app.config.ts` 只有 `ios:` 配置块，无 `android:`；
- `package.json` 只有 `ios:*` 脚本，无任何 android 脚本；
- `expo-build-properties`、bundleIdentifier 全为 iOS；无 `eas.json`（本地 `expo run:ios` prebuild）；
- README 标题即 "Multica Mobile (iOS)"。

后端地址通过环境变量切换：`.env.production` 中 `EXPO_PUBLIC_API_URL=https://api.multica.ai`。

**结论**：不需要从零重写原生 app。RTMultica 只需把上游现成的 RN app **补上 Android 配置、overlay
成自托管服务器、并建立 Android 构建流水线**——与现有桌面版 overlay 模式同构。

## 2. 目标与非目标

### 目标
- 产出一个**真原生**（RN 渲染原生组件）的 Android APK，连接自托管后端。
- 复用上游 `apps/mobile` 的全部业务功能，**功能跟随上游**、不自己实现业务 UI。
- overlay 层保持**最小、可维护**，上游升级时 re-sync 成本可控。
- 构建可在 CI 自动完成，复用现有 keystore 签名机制。

### 非目标
- 不重写任何业务功能，不 fork 上游 app 逻辑。
- 不做 iOS（上游已有 iOS 路径）。
- 本阶段不下线现有 Capacitor 套壳版（见决策：并行共存）。
- 不追求上架应用商店（用户动机是原生交互，非上架）。

## 3. 关键决策（已与用户确认）

| 决策 | 选择 | 理由 |
|---|---|---|
| 与现有套壳的关系 | **并行共存，新包名** | RN 版用独立包名，与套壳同时可装，便于对比/过渡；稳定后再决定是否下线套壳 |
| 构建基础设施 | **复用现有 GitHub Actions** | ubuntu runner 上 prebuild + gradle，复用 `SIGNING_KEY_BASE64` 等 secrets，可自动化 |
| Android applicationId | `top.naivehero.multica.rn`（**已确认**） | 与现有套壳 `top.naivehero.multica` 区分，避免安装冲突 |
| Android 显示名 | `Multica RN`（**已确认**） | 与套壳版 "Multica" 在桌面图标上可区分，便于并行安装时识别 |
| 后端 API 地址 | `https://mtcsrv.naivehero.top:8443`（**已确认**） | 对齐桌面版 `runtime-config.ts` 的 `apiUrl`；RN 需要的是 API host 而非 web host。ws 由 app 内部从 apiUrl 推导为 `wss://mtcsrv.naivehero.top:8443/ws` |
| Web 地址 | `https://mtc.naivehero.top:8443`（**已确认**） | 桌面版 `appUrl`；用于 `EXPO_PUBLIC_WEB_URL`，启用"复制链接/在网页打开"类菜单 |

## 4. 架构总览

沿用 RTMultica 既有的"**pin 上游 tag → overlay 配置 → 构建**"模式（当前桌面版 `desktop/build.sh` 就是这套）：

```
RTMultica repo
├── mobile/
│   ├── build-android.sh        # 本地构建脚本（镜像 desktop/build.sh）
│   └── overlay/                # 覆盖到上游 apps/mobile 的最小文件集
│       ├── .env.production        # EXPO_PUBLIC_API_URL → 自托管
│       └── config-patch/          # 注入 android 配置的补丁/脚本
├── projects/multica/           # 上游只读 clone（gitignored，已有）
└── .github/workflows/
    └── build-android-native.yml   # 新增：RN Android 构建流水线
```

上游 `apps/mobile` 被 checkout 到固定 tag，overlay 应用后 `expo prebuild --platform android`
生成原生 android 工程，再 gradle 出签名 APK。overlay 通过 git stash 在构建后还原，保持上游 clone 干净
（与 `desktop/build.sh` 的 `trap cleanup EXIT` 一致）。

## 5. 组件设计

### 5.1 overlay 内容（最小集）

1. **`.env.production`** —— 整文件替换，写入两个值（低 drift 风险）：
   - `EXPO_PUBLIC_API_URL=https://mtcsrv.naivehero.top:8443`（ws 由 app 内部推导，无需单独配置）
   - `EXPO_PUBLIC_WEB_URL=https://mtc.naivehero.top:8443`（启用"在网页打开"类菜单）

2. **Android 配置注入** —— 上游 `app.config.ts` 无 `android:` 块，必须补上。为降低上游升级 drift，
   **优先用脚本注入/合并而非整文件替换**（参考 `desktop/build.sh` 用 `node -e` 注入 `packageManager`
   的做法）。需注入的 `android:` 字段至少包括：
   - `package`: `top.naivehero.multica.rn`
   - 显示名 `Multica RN`（在 `app.config.ts` 的 `name` 中对 Android 分支处理，或注入 android 专属名）
   - `adaptiveIcon`（前景 + 背景色 —— 现有仅 iOS 单 PNG 图标，Android 需自适应图标）
   - `edgeToEdgeEnabled` / 状态栏
   - 权限（对齐 iOS 的 photo library：`READ_MEDIA_IMAGES` 等；相机/麦克风上游已禁用）
   - 若需要，`expo-build-properties` 补 android 段（minSdk / `buildReactNativeFromSource`）

3. **Release 签名注入** —— `expo prebuild` 生成的 android 工程默认 debug 签名。构建前需向生成的
   `android/app/build.gradle` 或 `gradle.properties` 注入 release signingConfig，读取 keystore
   环境变量。复用现有 CI 的 `SIGNING_KEY_BASE64` / `KEY_STORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD`。

### 5.2 构建流程（CI：`build-android-native.yml`）

1. checkout RTMultica；checkout 上游 `apps/mobile` 目标 tag（pin 在脚本顶部的 `MULTICA_VERSION`，
   与 `desktop/build.sh` 一致）。
2. 应用 overlay（.env + android 注入）。
3. 安装依赖（pnpm，monorepo；参考桌面版 `--ignore-scripts` 规避 web postinstall 的经验）。
4. `npx expo prebuild --platform android`（生成原生工程）。
5. 注入 release 签名；解码 keystore（`SIGNING_KEY_BASE64` → `keystore.jks`）。
6. `cd android && ./gradlew assembleRelease`（可选 ABI split，与现有 Capacitor workflow 一致）。
7. 收集 APK，发布到**独立 release tag**（如 `android-native-latest`，区别于现有 `android-latest`）。

### 5.3 版本与发布策略

- `MULTICA_VERSION`（上游 tag）pin 在构建脚本顶部，每次发版更新——与 `desktop/build.sh` 一致。
- 新包名是独立版本序列：`versionCode` 从 1 起单调递增（不接续套壳的 45）。
- `versionName` 建议跟随 RTMultica 发版号，便于统一沟通。
- 发布到 `android-native-latest` release，安装说明区分于套壳版。

## 6. 数据流

App 启动 → 读取编译期内联的 `EXPO_PUBLIC_API_URL`（Release 构建时 baked 进 bundle）→ 通过
`@tanstack/react-query` 等直连自托管后端 REST/API → 认证 token 存 `expo-secure-store`。
**无 WebView**，UI 全部由 RN 原生渲染。

## 7. 风险与未决项

| 风险 | 等级 | 缓解 |
|---|---|---|
| **小众原生依赖的 Android 支持未验证** | 🔴 高 | 见 Phase 0 spike。重点验证：`react-native-enriched-markdown`、`react-native-shiki-engine`、`input-otp-native`、`rn-emoji-keyboard`、`react-native-image-viewing`。任一不支持需替换/打补丁 |
| Android 图标 / 启动屏 / edge-to-edge 适配 | 🟡 中 | RN/Expo 标准流程，比 iOS 略繁琐但成熟 |
| `app.config.ts` 注入随上游升级 drift | 🟡 中 | 注入而非整替；每次 bump `MULTICA_VERSION` 时验证注入仍生效 |
| monorepo 依赖安装在 CI 的坑 | 🟢 低 | 复用桌面版 `--ignore-scripts` 等经验 |
| overlay / 签名 / CI | 🟢 低 | 与现有资产同构，已有可复用流程 |

**签名利好**：iOS 免费 Apple ID 有 7 天签名限制；Android 用自持 keystore **无此限制**，standalone
APK 可长期使用，比 iOS 侧更省心。

### 待确认项 —— 全部已确认
1. 后端 API 地址 → `https://mtcsrv.naivehero.top:8443`
2. 新包名 → `top.naivehero.multica.rn`；显示名 → `Multica RN`
3. `EXPO_PUBLIC_WEB_URL` → `https://mtc.naivehero.top:8443`

## 8. 实施阶段

- **Phase 0 — 可行性 spike（硬门槛）**：本地 clone 上游 → 加最小 `android:` 配置 →
  `expo prebuild --platform android` → `expo run:android`。目标：确认能编译跑通、逐个排查
  §7 的依赖兼容性。**此阶段结果决定后续投入规模**。
- **Phase 1 — 本地稳定**：修复 spike 暴露的依赖/配置问题，本地出可安装、连自托管后端的 Release APK。
- **Phase 2 — overlay 化**：把 Phase 1 的改动收敛成 `mobile/overlay/` + `mobile/build-android.sh`，
  上游 clone 保持干净、可还原。
- **Phase 3 — CI**：落 `.github/workflows/build-android-native.yml`，接入 keystore 签名，发布到
  `android-native-latest`。
- **Phase 4 — 发布与文档**：更新 `CLAUDE.md` 增加 RN Android 线说明；编写安装指引。

## 9. 验证策略

- **Phase 0/1 验证**：真机安装 Release APK，走通登录、主列表、消息/AI 流式、图片附件、Markdown 渲染
  （即 §7 高风险依赖对应的功能面）。
- **交互验证（对应用户核心诉求）**：系统返回键、原生手势、触感反馈、键盘避让、状态栏/沉浸式——逐项确认
  达到原生观感。
- **CI 验证**：workflow 产出可安装的签名 APK；版本号策略正确（versionCode 单调递增）。
- **回归**：确认与现有套壳版可并行安装、互不干扰。
