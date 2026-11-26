# 云笺 CloudJian — 方案设计文档

> **新人入口**：先读 [README.md](README.md)（阅读顺序与有效版本）。实现只认正文。

> 项目名：云笺（CloudJian）
> 版本：v1.13.7（图片可见性改为跟随笔记 · 笔记新增公开档位 · 成本不变）
> 部署区域：AWS 东京 ap-northeast-1
> 架构基调：全 Serverless、单数据桶 + 独立 state 桶、无独立数据库服务、Terraform + GitHub Actions 全自动化

> **修订史**：历史版本变更说明已移至 [云笺-修订史归档.md](云笺-修订史归档.md)。
> **实现只认本文件正文**；修订说明与正文冲突时以正文为准。

---

## 1. 项目概述

**云笺（CloudJian）** 是一套由单人发起、面向小团队（上限 100 人）的在线 Markdown 笔记系统。「云」对应云端存储与 CDN 分发，「笺」指一条条以文件形态存在的 Markdown 短札，也点明了云笺的形态：把纸笺放在云上，随写随存、按需共享。

云笺的核心诉求是在**不引入数据库服务**的前提下，用 S3 + Lambda 撑起完整的笔记管理、用户体系、共享协同与图床能力，并把基础设施成本压到接近免费额度。

基本信息与定位边界：

| 项目 | 说明 |
|---|---|
| 项目名 | 云笺（CloudJian） |
| 统一标识 | `cloudjian`（用于仓库名、资源前缀、Terraform 工作区，详见第 13 章） |
| 使用人群 | 管理员手动开通账号的内部小团队，上限 100 人 |
| 登录态 | AccessToken 与 IdToken 有效期均 20 小时（以 AccessToken 的 `exp` 为准），超时强制重新登录，不使用 Refresh Token |
| 终端适配 | 仅 PC 端，不做移动端适配 |
| 主题 | 暗色默认，支持 light/dark 切换 |
| 界面语言 | 简体中文 / English / 日本語，可扩展 |
| 成本目标 | 稳态基准 ≈ $0.55–0.67/月、活跃 ≈ $1.24–1.52/月、高负载 ≈ $2.40–2.94/月（中心值 $0.61 / $1.38 / $2.67；若 CloudWatch 日志不享 5GB 免费额度，上修至 ≈$0.91 / $1.98 / $3.87；**即唯一线上环境的 AWS 支出**；GitHub Actions 目标 $0（三仓公开，标准 runner 免费），不含审计增强项，算式见 12.8） |

---

## 2. 功能需求清单

### 2.1 用户与权限
- Cognito 托管认证，管理员手动添加用户，首次登录强制改密码
- 在线修改密码，修改后该账号全部既有会话在 ≤60 秒内失效（服务端注册表校验的固有延迟）
- 管理员前端可视化管理后台：用户列表、新建用户、禁用/启用、重置密码、角色调整
- 角色模型：`admin` / `user`，由 Cognito Groups 承载，**最终以服务端注册表为准**

### 2.2 笔记管理
- 多级嵌套目录 + 标签体系：本期只做**自由标签**（单篇 ≤20 个、单个标签 ≤24 字符，不支持层级、颜色、重命名与标签管理页，仅在属性面板增删）；`Frontmatter.tags` 为唯一真源，`index.tags` 只是可重建的派生缓存（v1.13.2，T-03）
- 新建、查看、编辑、删除；软删除进回收站，30 天后物理删除；**回收站内可主动彻底删除（单篇/批量/整目录/清空），无需等 30 天（v1.13.6）**
- 版本历史保留 30 天，支持任意版本对比与回滚
- 笔记列表分页
- 正文全文搜索（服务端执行，只返回命中分页）
- 单篇导出 `.md`，多篇批量打包 ZIP 导出

### 2.3 共享与协同
- 共享粒度：单篇笔记 + 整个目录（目录共享递归生效）
- 权限等级：只读 / 可编辑
- 非实时协同，基于 S3 条件写（If-Match）+ 单调版本号
- 冲突时提供**行级差异对比面板**，可看出新增/删除/修改的具体行，甚至行内字符级差异
- 冲突处理三选项：强制覆盖、放弃本地修改、手动合并

### 2.4 编辑器
- 组件：Vditor（React 封装版）
- 三种模式一键切换：纯编辑 / 左右分屏预览 / 所见即所得
- 扩展能力：全语言代码高亮、Mermaid 流程图、表格、任务列表、脚注、目录
- 数学公式：本期不做

### 2.5 图床
- 图片与笔记同桶不同前缀
- 图片可见性由用户按单张控制：公开 / 仅登录可见
- 粘贴、拖拽图片自动上传并插入 Markdown 链接
- 编辑器内置图片管理面板（浏览、插入、删除、切换可见性），不单独做一个图片管理站点
- 不做自动压缩与缩略图

### 2.6 国际化与多语言
- 界面支持简体中文（默认）、English、日本語三种语言，可后续扩展
- 语言切换即时生效，不需要刷新页面
- 语言偏好随账号同步，跨设备一致
- 日期时间按用户时区与所选语言格式化
- 用户笔记正文不做机器翻译，但标注语言以便检索
- **语言范围就此封版（v1.10 定稿，原 17.6）**：只做 `zh-CN` / `en-US` / `ja-JP` 三种，不新增第四种；同时**不要求语言级内容规范**（例如不强求日文笔记必须标 `ja-JP`，`lang` 字段缺失或为 `unknown` 时按正文启发式推断，仅用于检索不做校验）
- 错误提示、系统文案、管理后台全部走语言包，不硬编码中文

---

## 3. 技术架构

| 层级 | 选型 |
|---|---|
| 前端 | React + TypeScript + Vditor + react-diff-view + react-i18next；构建产线 **Node.js 24 LTS（`node-version: 24`）+ npm，锁 `package-lock.json`** |
| 后端 | AWS Lambda（**Python 3.14**）+ API Gateway **HTTP API**（v1.8 由 REST 切换） |
| 认证 | AWS Cognito 用户池（Lite/Essentials，万级 MAU 永久免费） |
| 存储 | 单数据桶（前缀隔离）+ 独立 Terraform state 桶 |
| 分发 | CloudFront + OAC + CloudFront Function（路径白名单）+ S3 静态托管 |
| 基础设施 | Terraform，state 存 S3 远程后端，S3 原生锁文件 |
| CI/CD | GitHub Actions + OIDC 临时凭证 |
| 区域 | ap-northeast-1（东京） |
| 域名 | CloudFront 分配域名，不绑自定义域名 |
| 工程组织 | 三仓分离：frontend / backend / infra，独立流水线；**单环境发布**（`dev` 即线上，`main` 只归档），见 12.4 |

### 3.1 请求链路

```
浏览器
  ├─ 静态资源  ──▶ CloudFront ─▶ Function(白名单) ─▶ S3 /web/*
  ├─ 公开图片  ──▶ CloudFront ─▶ Function(白名单) ─▶ S3 /users/*/assets/public/*
  ├─ 私有图片  ──▶ S3 预签名 URL 直连（TTL 5 分钟，不经 CloudFront）
  └─ 业务 API  ──▶ HTTP API（JWT 授权器：验签 / iss / 受众 / exp）
                     └─▶ Lambda（中间件：token_use + 注册表 status/role/auth_time）─▶ S3 私有前缀
```

### 3.2 Parquet 依赖的部署方式

Parquet 读写库无法直接打进 Lambda 部署包，采用 **Lambda Layer** 独立封装：

- 依赖选型：`fastparquet` + `python-snappy`（实际含 numpy/pandas/cramjam 依赖，Layer 压缩后为数十 MB 量级，冷启动增加约 80–150ms）
- 构建方式：GitHub Actions 用 AWS 官方 Lambda Python 镜像编译，产出兼容 Amazon Linux 2023 的二进制
- 版本管理：Layer 与函数的创建、发布、别名切换全部由**后端工程**负责，infra **不管理任何 Lambda 资源**（契约见 12.3）

> 元数据已确认保留 Parquet（决策记录见 15.3）。若日后改 gzip JSON，本节与 Layer 相关内容整体删除，冷启动可减少约 100ms、CI 少一条编译链路。

---

## 4. 认证与用户体系

### 4.1 为什么选 Cognito

100 人规模下 Cognito 的 Lite / Essentials 套餐提供**每月 10,000 MAU 永久免费额度**，不受 12 个月免费期限制，实际零费用。相对 S3 自建账号体系，省掉密码哈希存储、登录失败锁定、密码找回、账号禁用等一整套安全逻辑的开发与维护。

### 4.2 登录与鉴权流程

1. 前端用 `amazon-cognito-identity-js` 走 **USER_SRP_AUTH**，密码不明文出网
2. 若返回 `NEW_PASSWORD_REQUIRED` challenge（管理员新建用户或重置后的首次登录），前端跳「设置新密码」页，用 `RespondToAuthChallenge` 完成挑战后方可拿到 Token
3. IdToken 中携带 `sub`（用户 UUID）与 `cognito:groups`
4. 前端同时保存 IdToken（仅用于本地展示用户信息）与 **AccessToken**（调 API 与 `GlobalSignOut` 用），所有业务请求在 `Authorization` 头携带 **AccessToken**
5. **网关先验一道**（HTTP API JWT 授权器，见 12.1）：签名、`iss`、受众（App Client ID）、`exp`/`nbf`/`iat` 在网关层就判定，不合格的请求不进 Lambda
6. **Lambda 中间件再验**（详见 4.6）：直接取网关注入的 `authorizer.jwt.claims`（不再重复验签，见 12.1 方案 A）→ 校验 `client_id`/`token_use=access`/`exp` → 查注册表 `status`/`role`；`requestContext.authorizer` 缺失直接 401
7. **AccessToken 与 IdToken 都设为 20 小时**（Cognito 里两者是独立配置，access token 默认 60 分钟；只设 ID token 会导致用户每小时被 401 踢回登录页 —— F5），业务请求的有效期以 **AccessToken 的 `exp`** 为准；**前端不保存、不使用 Refresh Token**，到期直接清空跳登录页

> 取舍记录：Cognito 的 Refresh Token 有效期最小 1 天、不能设为 0（设 0 会回退默认 30 天）。云笺的做法是「配置上不申请、代码里不使用」，20 小时强制重登由前端拦截器与 AccessToken 自身的 `exp` 共同保证，不依赖服务端删除 Refresh Token。

### 4.3 角色模型

- 使用 **Cognito Groups** 承载 `admin` / `user`，不再使用 `custom:role`
- 原因：自定义属性一旦创建不可删除、不可改名、不可改类型，且 App Client 默认可写 → 存在用户自助提权路径（审核 R3）
- App Client 的 `WriteAttributes` 最小化为空集，用户无法通过 `UpdateUserAttributes` 改任何业务属性
- Groups 仅用于前端菜单显隐，**后端一切权限判断以 `_registry.parquet` 的 `role` 字段为准**

### 4.4 用户 ID 与命名空间

- 用户 UUID 直接使用 Cognito 的 `sub`，天然全局唯一且不可枚举
- 该 UUID 作为 S3 中该用户全部数据的前缀名，是所有隔离的基础

### 4.5 管理员开通用户

后台页面填写：用户名、初始密码、可选邮箱、角色。

**密码策略（v1.13.5，P-B）**：Cognito User Pool 统一配置为长度 **8–20**、至少含**大写、小写、数字**各一、**不强制特殊符号**；后台初始密码与 4.2 首登改密、4.7 自助改密共用同一规则，前端提示文案三语一致。不配置该项时 Cognito 默认要求符号，会出现「后台建号成功、用户改密必失败」的口径裂缝。

提交后 Lambda 依次执行：

1. 调用 `AdminCreateUser` 创建用户，置为 `FORCE_CHANGE_PASSWORD` 状态，并按角色加入对应 Group
2. 初始化该用户 UUID 前缀下的目录结构与空索引（`notes/`、`trash/`、`versions/`、`assets/public/`、`assets/private/`、`shares/`、`index.parquet`）
3. 写入全局注册表 `_registry.parquet` 一条记录（`status=active`）

初始超级管理员通过 Terraform 预先创建。

### 4.6 Token 校验与撤销的落地方式

仅凭 JWT 自包含的信息（含网关的离线验签结果），无法感知「已禁用、已降权、已改密」。云笺的解法：

1. **Lambda 每次请求都读注册表**，比对 `status=active` 与 `role`（Token 只负责「你是谁」，权限与状态一律以注册表为准）
2. 注册表按 Lambda 实例缓存 60 秒（文件体积几十 KB，读取代价可忽略），因此禁用用户最长 60 秒内失效
3. **改密另用 `password_changed_at` 判定**：AccessToken 自带 `auth_time`，若 `auth_time < password_changed_at` 直接 401。原因：`GlobalSignOut` 只在 Cognito 侧撤销，网关的 JWT 授权器验签仍会放行到 `exp`（最长 20 小时），只比对 `status`/`role` 兜不住改密场景（P1-5）
4. **单位换算必须显式写死（F9）**：`auth_time` 是 Unix **秒**，`password_changed_at` 建议统一存**秒**（注册表里即存秒，避免两套单位）；若沿用毫秒则比较前先 `password_changed_at // 1000`。这是同类实现里最常见的翻车点，列为实现期第一条单测用例（改密后同一秒内的旧 Token 必须 401、新 Token 必须 200）
5. 中间件对网关 claims 做**二次比对**：`iss`、`client_id`、`token_use=access`、`exp`。**Lambda 不碰 JWKS**（方案 A：验签已在 12.1 的网关授权器完成，那里才有 JWKS 缓存），因此不存在「本地 JWKS 缓存 1 小时」这套逻辑
6. **`token_use=access` 是硬门槛**：HTTP API 的 JWT 授权器无法区分 AccessToken 与 ID Token（ID Token 的 `aud` 恰好也是 App Client ID，在**未声明 scope** 时可合法过网关），因此这一行必须在中间件里存在，缺失即等于开放 ID Token 冒充（见 12.1 门禁分工）

### 4.7 修改密码

- 用户自助：Cognito `ChangePassword`（需原密码），成功后用**存有的 AccessToken** 调 `GlobalSignOut`，再清空本地两个 Token
- 管理员重置：Lambda 用自身 IAM 角色调 `AdminResetPassword` + `AdminUserGlobalSignOut`，**不由前端调用 Admin 接口**
- 两条路径都要求前端清空本地 Token，旧 Token 由 4.6 的三重校验（status / role / `auth_time` vs `password_changed_at`）在 ≤60 秒内拦下
- App Client 开启 `EnableTokenRevocation=true`。**注意这层的实际作用有限（F10）**：撤销只在 Cognito 自己校验 Token 时生效，云笺的 Lambda 不验签、只读网关 claims，同样查不到撤销列表，所以它是「换 Token 的接口（如改密、刷新）会被 Cognito 拒绝」，而不是「旧 AccessToken 立刻失效」。真正兜住改密的是第 3 条的 `auth_time` 比对；本条不按「双保险」设计验收

---

## 5. 存储设计

### 5.1 桶与前缀划分

- **数据桶** `cloudjian-data-tokyo`：承载全部业务数据与现代码
- **状态桶** `cloudjian-tfstate-tokyo`：仅放 Terraform state，与业务数据物理分离（v1.11 单环境，恢复为单桶；workspace 仍用独立 `tokyo`）
- 数据桶内不再保留 `tf-state/` 前缀

```
cloudjian-data-tokyo/
├── web/                              # 前端静态资源（匿名公开）
└── users/
    ├── _registry.parquet             # 全局用户注册表
    ├── _share_inbox.parquet          # 共享收件箱反向索引（读取侧唯一入口）
    ├── _team_config.json             # 团队级配置（默认可见性/强制私有），唯一真源，5 分钟缓存
    └── {user-uuid}/
        ├── notes/
        │   └── {分类路径}/
        │       ├── {slug}.md         # 笔记正文 + YAML Frontmatter（含 note_id）
        │       └── .dir_meta.json    # 目录元数据（共享配置、描述）
        ├── trash/                    # 回收站，30 天生命周期删除
        ├── versions/
        │   └── {note_id}/{timestamp}.md   # 历史版本，30 天生命周期删除
        ├── assets/
        │   ├── public/{fingerprint}/{file}   # 公开图片
        │   ├── private/                       # 私有图片（仅 S3 预签名 URL 访问，不经 CloudFront）
        │   └── _trash/{asset_id}/{file}       # 随笔记删除移入，30 天标签生命周期清理
        ├── shares/                   # 我发出的共享关系（单一写入者：本人）
        ├── search/
        │   └── shard-{n}.json.gz     # 全文搜索分片索引（从 Frontmatter 与正文派生）
        ├── jobs/                     # 异步任务状态（目录搬移、批量导出、目录级恢复）
        ├── exports/                  # 打包产物，1 天生命周期删除
        ├── index.parquet             # 笔记主索引（可重建的派生缓存）
        └── profile.json              # 个性化配置（ui_lang、tz、theme、editor_mode、list_sort、page_size）
```

### 5.2 笔记身份与文件命名

文件名仍采用**标题 Slug**（保留可读性），但**身份不再由文件名承担**：

| 概念 | 承载方式 | 说明 |
|---|---|---|
| 显示用文件名 | `{slug}.md` | 英文转小写连字符；中文转无声调拼音；同目录重名追加 `-1`/`-2` |
| 唯一身份 | Frontmatter 的 `note_id`（ULID，26 位） | 全局唯一、创建后永不改变；索引主键、版本目录、共享引用、回收站恢复全部用它 |
| 唯一性约束 | `category_path + slug` | 写入前校验，仅约束「显示路径不重复」 |

这样在不牺牲 Slug 可读性的前提下，彻底消除审核 R4 指出的「跨目录同名主键冲突」：

- `工作/技术/周报` 与 `生活/周报` 可以是相同 slug、不同 `note_id`，互不干扰
- 移动/重命名只改路径与文件名，`note_id` 不变，版本历史不会串篇
- 版本目录用 `versions/{note_id}/`，与路径解耦

文件内容结构：

```markdown
---
note_id: 01JCF3K8QW7N2R5T9YBX4M6VHA
title: AWS Lambda 冷启动优化
slug: aws-lambda-lengqi-dong-you-hua
category: 工作/技术/AWS
tags: [aws, lambda, 性能]
lang: zh-CN                       # 笔记正文语言，仅作检索提示；缺失不报错（见 5.3.2）
created_at: 2026-11-25T10:00:00+08:00
updated_at: 2026-11-25T14:30:00+08:00
version: 12                       # 单调递增版本号，用于冲突检测
---

正文 Markdown 内容……
```

### 5.3 元数据方案：Parquet

#### 5.3.1 选型说明与既有取舍

结构化元数据使用 Apache Parquet 列式存储。需要诚实记录它的真实收益与代价（审核 R9 的意见已部分采纳）：

**真实收益**

- 体积约为 JSON 的 1/4 ~ 1/6（100 人合计约 6MB → 约 1.2MB，S3 存储成本差约 $0.0001/月）
- 可直接被 Athena / DuckDB 查询，具备离线分析与运维排查能力

**实际收益有限的部分（已修正 v1.0 的夸大表述）**

- v1.0 称「列裁剪降低内存开销」，但由于写入与读取均是全量读-全量写，列裁剪只在「导出/分析」路径有效，在线接口路径收益为零。本版不再把它作为选型理由。
- v1.0 预留的 `analytics/` 自动导出工作流本期不做（无需求），Parquet 的分析能力改为「需要时用 DuckDB 现场查」。

**代价与兜底**

- 二进制不可在控制台查看编辑 → 提供三件运维工具（见 5.3.6）
- 依赖走 Layer，冷启动 +约 100ms
- Schema 变更需版本字段兼容

**保留 JSON 的部分**：笔记正文 Frontmatter、`.dir_meta.json`、`profile.json`、`jobs/*.json`。理由是小文件 Parquet 文件头开销大于数据本身，且这些内容需要可手动编辑与快速排查。

#### 5.3.2 单用户索引 `index.parquet`

| 字段 | 类型 | 说明 |
|---|---|---|
| `note_id` | string | **主键**，ULID，来自 Frontmatter |
| `title` | string | 标题 |
| `slug` | string | 文件名主体（可读标识，非主键） |
| `category_path` | string | 多级分类完整路径，如 `工作/技术/AWS` |
| `tags` | list\<string\> | 标签数组 |
| `lang` | string | 正文语言：`zh-CN` / `en-US` / `ja-JP` / `unknown`；**缺失或 `unknown` 时由建立索引阶段按字符集比例启发式推断**（CJK 假名 → `ja-JP`，汉字为主 → `zh-CN`，拉丁为主 → `en-US`），结果只写入检索字段，**不回写 Frontmatter、不做校验**（X10） |
| `created_at` | int64 | 创建时间戳（毫秒，UTC） |
| `updated_at` | int64 | 更新时间戳（毫秒，UTC） |
| `version` | int64 | 单调递增版本号 |
| `is_deleted` | boolean | 软删除标记 |
| `deleted_at` | int64 | 删除时间戳，未删除为 0 |
| `own_share` | string | 我给出的共享范围：`none` / `read` / `edit` |
| `visibility` | string | 笔记可见性：`private`（默认，仅 owner 与已共享成员）/ `public`（持公开链接匿名可读）；真源是 Frontmatter，索引为派生缓存（v1.13.7） |
| `file_size` | int32 | 笔记文件字节数 |

> 说明：Frontmatter **不记录任何共享信息**（共享的唯一真源是 `shares/{share_id}.json`），索引里的 `own_share` 只是可重建的聚合缓存；被共享给我的内容由 `_share_inbox.parquet` 汇总。

> 补充（v1.13.2，T-03）：`tags` 的真源是笔记 Frontmatter 的 `tags` 字段，索引里的 `tags` 列同样是派生缓存；`rebuild_index.py` 以 Frontmatter 为准重建，两者不一致时以 Frontmatter 为准（与 7.1 的单一数据源表一致）。

#### 5.3.3 全局注册表 `_registry.parquet`

| 字段 | 类型 | 说明 |
|---|---|---|
| `user_uuid` | string | 用户 UUID（Cognito sub），主键 |
| `username` | string | 用户名，唯一 |
| `role` | string | `admin` / `user` |
| `status` | string | `active` / `disabled` |
| `created_at` | int64 | 创建时间戳 |
| `last_login_at` | int64 | 最后登录时间戳 |
| `password_changed_at` | int64 | 最近一次改密时间戳，用于让旧 Token 在 ≤60 秒内失效 |

#### 5.3.4 读写流程

1. Lambda 从 S3 下载 Parquet → fastparquet 载入内存
2. 内存中完成增删改、分页、筛选、排序
3. 序列化回 Parquet，全量写回 S3

#### 5.3.5 并发控制

统一使用**条件写**，不再依赖「先比对 ETag 再写」这种有 TOCTOU 窗口的做法：

1. 读取时同时拿到对象内容与 `version`（存在 Frontmatter 与索引中）
2. 写回时用 `If-Match: <ETag>`，并且先写入 `version+1`
3. 结果分支严格区分：
   - `200` → 成功
   - `412 Precondition Failed` → 版本已变，进冲突流程（笔记正文走第 7 章差异面板；索引走自动重试）
   - `409 Conflict` → 并发删除类冲突，按删除/重建处理（响应体为 9.4 的 `DELETE_CONFLICT` 信封）
   - `404 Not Found` → 对象已被删除
4. 索引写入失败时重试「读取-修改-写入」最多 3 次，每次重新取 ETag
5. IAM 上确保执行角色同时具备 `s3:GetObject` 与 `s3:PutObject`（If-Match 需要读权限）
6. 启用 **S3 Versioning**，作为误覆盖最后一道兜底（ETag 相同但内容被回滚的 ABA 场景，靠 VersionId 追溯）

#### 5.3.6 运维工具（补 v1.0 缺口）

| 工具 | 用途 |
|---|---|
| `scripts/rebuild_index.py` | 全量扫描 `notes/` 的 Frontmatter，重建 `index.parquet` 与 `search/` 分片；索引视为派生缓存，可随时重建 |
| `scripts/inspect_parquet.py`（DuckDB） | 本地一行 SQL 查看任意索引内容、按条件筛选、导出 CSV 供人工修正 |
| 后台「导出元数据」按钮 | 管理员把 `_registry.parquet` 或指定用户索引导出为 CSV |

---

## 6. 笔记与目录管理

### 6.1 目录体系

- 目录即 S3 前缀，多级嵌套直接映射为多段路径
- 每个目录放一个 `.dir_meta.json`，记录目录描述、共享配置、创建时间；Lambda 遍历时自动过滤 `.` 开头的文件
- 目录操作：新建、重命名、移动、删除（删除即把子树整体移入 `trash/`，30 天后清理）

**目录移动/重命名改为可续跑的批量任务**（原 v1.0「逐对象 Copy+Delete」会撞网关 30 秒集成超时，且无补偿）：

1. 建立任务记录 `jobs/{job_id}.json`：`{status: running, cursor, total, moved: []}`
2. 每次 Lambda 调用搬移最多 100 个对象（约 200 次请求，**预算 15 秒**、函数超时 25 秒、留 10 秒余量；超时则写回游标由下一次调用续跑），写回游标。**目录搬移的 Copy 用 `TaggingDirective=COPY`、不加 TTL 标签**（与回收站的 `copy_with_retention` 是两个封装，不要复用）
3. 前端轮询直到 `status=done`；中途失败可从 `cursor` 续跑，已搬对象靠 `moved` 清单幂等跳过
4. 任务结束统一刷新索引与搜索分片；**索引未刷新前，整棵子树进入只读态**（v1.13.2，T-08）：列表按旧路径只读展示，同时拒绝该子树下的新建、编辑、删除、移动、共享变更与导出，统一返回 `409 JOB_RUNNING`；前端按 job 状态直接禁用按钮，不做「先允许再报错」
5. **任务收尾必须同步刷新共享引用**（v1.13.2，表外缺口③）：搬移/重命名完成后逐条检查 `shares/*.json`，把 `target_dir` 改写为新路径，并同步更新 `_share_inbox.parquet` 的对应记录。该步骤此前只写在 6.5 的恢复 job 里，搬移侧漏写会让「已共享目录」的 `target_dir` 指向不存在的路径

**目录级恢复复用同一套 jobs**：任务体 `{type: restore_dir, root, cursor, restored: []}`，从 `trash/` 反向 copy 回 `notes/`（走 `copy_with_retention` 的逆操作，即拷贝后**去掉** `cj:retention=30d` 标签，否则恢复后的笔记 30 天后又被生命周期删掉）。

### 6.2 列表与分页

- 列表数据来自 `index.parquet`，Lambda 内存分页（`page`、`page_size`，默认 20）；每条额外返回 `visibility`，前端对公开笔记打「公开」徽标（v1.13.7）
- 排序默认按 `updated_at` 倒序，可切换创建时间、标题
- 支持按 `category_path` 前缀筛选（进入某目录只显示该子树）、按标签筛选
- 「共享给我」列表**只读 `users/_share_inbox.parquet`**（7.2 的收件箱反向索引），与「我的笔记」分开返回；**不得遍历 `shares/` 汇总**（照旧文案实现正好踩全库 LIST 禁令 —— X7）

### 6.3 全文搜索（服务端执行）

v1.0 的「全量下发正文给前端搜索」会撞 API Gateway 10MB / Lambda 同步 6MB 硬限制，且在共享撤销后无法回收正文。本版改为服务端搜索：

1. **分片索引**：`search/shard-{n}.json.gz`，每片最多 256 篇，含 `note_id`、`title`、`category_path`、`tags`、正文纯文本、`updated_at`
2. 分片归属由 `hash(note_id) % shard_count` **固定映射**，一篇笔记永远落在同一分片，避免「相邻笔记挤在同一片、并发编辑互相 412」；**`shard_count` 在契约中固定为 32**（32 × 256 = 8192 篇/用户容量，覆盖 14.1 的 5000 篇与 C 档人均 5000 篇；原定 16 只能装 4096 篇，与容量表矛盾 —— F8），不随笔记数动态调整；保存/删除时增量更新该片（If-Match 条件写 + 指数退避重试）；扩容 `shard_count` 属一次性全量重建，归入 14.2 升级路径
3. 搜索请求：Lambda 并发读取该用户所有分片（1000 篇约 4 片），在内存中做大小写不敏感的子串匹配 + 标签匹配，按 `updated_at` 排序
4. **只返回命中分页**：每页 20 条，每条含 `note_id`、标题、路径、命中片段前后各 60 字摘要，单次响应控制在 **512KB 以内**（HTTP API 按 **512KB 增量计量**，超过即按 2 个请求计费 —— G8；每页 20 条摘要实际仅几十 KB，量级可忽略，但口径必须写死）
   - **结果归属标识（v1.13.2，T-13）**：每条额外返回 `origin`（`own` / `shared`）与 `owner_name`（仅共享结果），前端用「共享」徽标区分；共享结果的 `path` 只返回**相对共享根**的那一段路径，不回传 owner 的完整目录树，避免越权泄露目录结构
5. 共享笔记的正文不进入我的搜索分片；搜索共享内容时按 `shares/` 指向的 `owner` 分片单独查（权限校验后返回）
6. 超出单次上限时返回 `has_more=true`，前端分页续查

> 若后续引入 OpenSearch（见 14.2），本节的分片索引可整体替换，接口契约不变。

### 6.4 版本历史

- 笔记每次写入前，把旧版内容写入 `versions/{note_id}/{timestamp}.md`
- 版本列表按时间倒序返回，支持「与当前版本对比」和「回滚到该版本」
- 回滚本身也视为一次更新，同样先留存当前版本，保证可回溯
- 版本目录以 `note_id` 命名，路径移动不影响历史连续性

### 6.5 软删除与回收站

- 删除：文件从 `notes/` 移到 `trash/`（保持相对路径）—— 这是 **CopyObject + DeleteObject**，不是 PUT，索引 `is_deleted=true`、写 `deleted_at`
- **Copy 必须 `TaggingDirective=REPLACE`** 并写入 `cj:retention=30d`（F3）：CopyObject 默认 `TaggingDirective=COPY`，普通笔记本来不带 retention 标签，若照搬标签，进回收站的对象永远不命中生命周期规则 —— P0-1 的静默失效只是换了个入口。实现走 `copy_with_retention(src, dst, retention="30d")`，与 `put_with_retention()` 分开封装
- **回收站按原目录树展示（v1.10 定稿，原 17.2）**：S3 没有目录实体，删目录后 `trash/` 下只是一批带前缀的 key，因此页面**不做打平列表** —— 读取随迁移一起进 `trash/` 的 `.dir_meta.json`，在内存把树重新拼出来（`📁 项目A / 📁 子模块 / 📄 方案.md`），支持目录级一键恢复与单篇恢复
- 目录级恢复是**异步 job**（复用 6.1 的 jobs 机制）：批量 copy 回 `notes/` 原路径，并同步刷新 `index.parquet`、`_refs.json`、搜索分片；**不做同步接口**（深目录会撞 25 秒超时）
- 回收站树结构按用户缓存 **15 分钟**，避免每次打开都大量 GET `.dir_meta.json`
- **「剩余天数」口径（v1.13.2，T-04）**：S3 标签过期按对象的 `LastModified` 计，而进 trash 是一次 CopyObject（新建对象），所以 30 天起点 **≈ 删除动作时刻，与原笔记的写入时间无关**；恢复后再次删除会重新计时。前端文案统一写「约 N 天后清理」，N 由列表接口返回的 `LastModified` 计算、与 30 天取差，前缀内 `list-objects-v2` 本就返回该字段，不额外收费；不写「已于某日删除，将于某日清理」这种看似精确、实则会漂移的说法
- 冲突：恢复时原路径已有同名笔记/目录，自动追加 `-1` slug 后缀，不覆盖现有内容
- **恢复必须去掉 retention 标签**（`TaggingDirective=REPLACE` 且不带 `cj:retention`），无论单篇还是目录级；否则恢复出来的笔记会在 30 天后被生命周期规则再删一次
- **单篇删除没有 `.dir_meta.json` 可读（X8）**：单篇恢复直接按 `trash/` 下的 key 路径反推原 `category_path`（`trash/{分类路径}/{slug}.md`），不依赖目录元数据；只有目录级恢复才读随迁的 `.dir_meta.json`
- **恢复 job 与目录搬移共用同一套 jobs 机制，但 copy 封装必须分开（Y5）**：目录搬移用 `TaggingDirective=COPY`（保留原标签），恢复用 `TaggingDirective=REPLACE` 且不带标签（去掉 30 天保留）；两者都写在 `storage/retention.py`（17.9 白名单内），不新增裸 `copy_object`。**字面共用 `copy_with_retention` 会把 `cj:retention=30d` 拷回 `notes/`，恢复的笔记 30 天后又被删（F3 复活）**；任务完成后除索引与搜索分片外，还须刷新 `shares/` 与 `_share_inbox.parquet`——被删时这些共享记录若已失效，恢复后要按原 `target_dir` 重建或标记为 `target_missing`
- 重名 `-1` 后缀只作用于笔记/目录 key；若原路径是共享目标，恢复后同步更新 `shares/*.json` 的 `target_dir`（X18）
- 物理清除：**写入时打对象标签 `cj:retention=30d`**，由桶级生命周期规则按标签过滤，30 天后过期删除。写入统一经 `put_with_retention()` / `copy_with_retention()` 封装，CI 先例扫描禁止裸 `put_object`、`copy_object`、`upload_file`（约束见 17.8–17.10）。注意不能用 `users/*/trash/` 这类带通配符的前缀 —— S3 生命周期前缀是字面前缀匹配、**不支持 `*`**，配了不报错但命中 0 个对象（P0-1）

**回收站彻底删除（v1.13.6，P-10/P-25）**：

- **四类粒度**：`scope=note`（单篇）、`notes`（批量 ≤200 篇，仅笔记）、`dir`（整个回收站目录子树）、`all`（清空回收站）。目录节点不参与多选；多选只在回收站视图出现，目录列表/搜索仍无多选。
- **一律异步**：`POST /trash/purge` 返回 202 + `job_id`，单篇也走 job。原因是一篇笔记牵连正文对象、`versions/{note_id}/` 整前缀、`assets/_trash/` 图片、`shares/` 与收件箱条目，对象数不可预估，同步接口会撞 25 秒函数超时（9.1）。
- **以索引为状态机**：先在 `index.parquet` 条件写 `purge_state=pending`，再逐批删对象（每批 ≤100 key，写 `cursor`），最后以 `pending` 为条件物理移除索引行。**禁止先删索引再删对象**——否则中途失败会留下「用户看不见、对象仍在」的僵尸数据，且无入口再触发清理，只能等 30 天。
- **删除范围**：`trash/{category_path}/{slug}.md`、`versions/{note_id}/` 整前缀（不留最后一份）、`assets/_trash/{asset_id}/`（仅 `_refs.json` 中 `ref_count` 归零者，仍被他人引用的只清本条引用）、`shares/*.json` 与 `_share_inbox.parquet` 中命中的记录、重建受影响的 `search/shard-{n}`（只重建命中分片）。
- **互斥与幂等**：purge 与 restore 会改同一批 key，同一用户同一 `root` 只允许一个 job，冲突返回 409 `JOB_RUNNING`；`purged[]` 记录已处理 key、`DeleteObject` 本身幂等，重复提交已不存在的项进 `rejected`（`TRASH_ITEM_NOT_FOUND`）而不是整体失败；不用 `If-Match`（回收站内容不可编辑，版本号无意义）。
- **与 30 天规则的关系**：purge 是「提前 `DeleteObject`」，不是新增删除策略、也不改标签来延期/加急；job 失败时对象仍在，30 天后由标签规则兜底清理。生命周期规则因此**必须保留**，它是 purge 的失败兜底，不是冗余。
- **确认强度由服务端复核**：`notes` 必须 `ack=true`，`all` 必须 `confirm="EMPTY_ALL"`（固定常量，不随语言变化）；前端展示的「清空 / Empty / 空にする」只是本地化 UI 文案，提交时映射为该常量。

### 6.6 导出

- 单篇：Lambda 返回 5 分钟有效的预签名 GET URL，浏览器直下
- 批量 ZIP：Lambda 生成 ZIP 写入 `exports/{job_id}.zip`，写入时打标签 `cj:retention=1d`，由桶级规则按标签在 1 天后删除；写入完成后返回**预签名下载 URL**（有效期 10 分钟）
- 大批量（> 200 篇或 > 20MB）：改为异步任务，前端轮询 `jobs/{job_id}.json` 状态，完成后取 URL；不做同步内存打包，规避网关 30 秒集成超时与 Lambda 同步 6MB 响应限制
- ZIP 保留目录结构，文件名使用 `slug.md`，同名冲突时以 `note_id` 前缀消歧
- **支持「整个目录导出为 ZIP 并保留目录结构」（v1.10 定稿，原 17.3）**：选目录即递归打包其下全部笔记与子目录层级；超过 200 篇或 20MB 自动转异步 job，与单篇导出共用同一套 `exports/` + 预签名流程
- **参数契约（X18）**：`POST /export` 入参三选一 —— `{note_id}`（单篇）、`{category_path, recursive: true}`（目录）、`{category_path, recursive: false}`（仅该层）；**导出目标必须是「我拥有的目录」**，共享目录不可导出（不是我的资产，且会绕过共享权限边界），需要时由 owner 导出
- 目录 ZIP 内的路径统一以所选目录为根（不写 `users/{uuid}/` 前缀），空目录保留为 `dir/` 条目；`-1` 冲突后缀只在同层同名时追加

---

## 7. 共享与协同

### 7.1 单一数据源原则

明确「谁是真源、谁是缓存」，消除 v1.0 的双写矛盾：

| 数据 | 真源 | 派生/缓存 |
|---|---|---|
| 笔记内容与元数据 | 笔记 `.md` 的 Frontmatter + 正文 | `index.parquet`、`search/shard-*.json.gz` |
| 目录与目录共享配置 | `.dir_meta.json` | 索引中的 `category_path` |
| 我发出的共享关系 | `shares/{share_id}.json` | 索引中的 `own_share` 字段 |

派生数据可随时由 `rebuild_index.py` 从真源重建；任何「索引与真源不一致」的争议，以真源为准。

### 7.2 共享关系存储与收件箱索引

**写入侧：每条共享一个文件，单一写者**

- `users/{owner_uuid}/shares/{share_id}.json`

```json
{
  "share_id": "sh_01JCF4...",
  "target_type": "note",
  "target_note_id": "01JCF3K8QW7N2R5T9YBX4M6VHA",
  "target_dir": "工作/技术/AWS",
  "grantee": "3f2a...c1",
  "level": "edit",
  "created_at": 1764000000000
}
```

- 只有共享者本人的请求会写这个对象，不存在跨用户索引双写，S3 无事务的问题自然消失（审核 R7）
- 500 篇目录共享给 3 人 = 3 条目录级记录，不展开为 500 条
- **共享成员的选择方式（v1.13.2，T-07）**：共享面板用「成员列表 + 前缀搜索」，数据源是 `_registry.parquet` 的 `username` / `user_uuid` / `role`（单对象 GET，沿用 4.6 的 60 秒实例缓存），零新增存储与接口成本；**不显示在线状态**——本期没有任何实时通道，承诺在线状态等于造假。共享目标只接受 `status=active` 且不等于本人的用户，命中不存在或已禁用时返回 `400 USER_NOT_FOUND` / `400 USER_DISABLED`（错误码表见 9.4）

**读取侧：集中收件箱索引，禁止全库 LIST**

v1.5 让「共享给我」遍历 `users/*/shares/`，这是新的成本炸弹（复审 N5）：S3 LIST 与 PUT 同价 $0.005/千，是 GET 的 12.5 倍；100 个用户前缀逐个列 ≈ 101 次 LIST/次，按实例级缓存每月约 64 万次 LIST ≈ **$3.2/月**，单项就超过基准档总预算。本版改为反向索引：

- 维护单一对象 `users/_share_inbox.parquet`，字段：`grantee`、`share_id`、`owner_uuid`、`target_type`、`target_note_id`、`target_dir`、`level`、`updated_at`
- 共享创建/撤销时，share-service **幂等更新**该对象（If-Match 条件写 + 指数退避重试）。注意它不是「无冲突的单写点」：全队任何人的共享创建/撤销都写这一个对象，属于热对象上的乐观锁串行化（F6）
- **重试 3 次仍 412 → 直接返回 500「共享操作失败，请重试」并打告警指标**，不允许静默成功或吞掉；共享列表读侧有 15 分钟缓存，短暂失败不影响读
- 对账任务**每日一次**（丢失窗口 1 天；改每周只是把窗口拉到 7 天，且对账跑在 Lambda 上，不消耗 GitHub Actions 分钟数 —— 「省 CI 分钟」的理由不成立，F6）。真正改周更的是 Actions 侧的漂移检查与契约校验
- 读取「共享给我」= 读 1 次该对象，按 `grantee` 过滤，Lambda 实例内缓存 15 分钟
- **每周**一次对账任务：扫描 `shares/*` 重建收件箱索引（`rebuild_index.py` 的子命令），修正漏写/错写；调度与目标函数见 12.3
- 成本：读取从 O(全库 LIST) 降为 1 次 GET + 少量 PUT，月成本 <$0.05

**为什么不用「登录时构建 + 写 profile.json」**：登录触发仍要 LIST 一次（100 用户 × 每天约 1.4 次登录 ≈ 1.4 万次 LIST/月 ≈ $0.07），虽可接受，但实时性差（共享变更后收件人看不到）、且把缓存写进用户配置对象放大 Versioning；集中索引在成本与一致性上都更优。

### 7.3 权限模型

| 粒度 | 存放位置 | 说明 |
|---|---|---|
| 目录共享 | `.dir_meta.json` 的 `shared_with` | 递归作用于该目录下所有子目录与笔记 |
| 单篇共享 | `shares/{share_id}.json` | 优先级最高，覆盖继承来的目录权限 |

**权限继承规则**：单篇共享 → 逐级向上查目录 `shared_with` → 都没有则不可见。同一用户命中多处时取最高等级（`edit` > `read`）。

**共享被撤销时的处理（v1.13.2，T-10）**：撤销后收件箱索引与「可见目录有效权限」预计算各自 15 分钟内收敛，这是**已知取舍**（无推送通道，不做服务端实时踢人）。已打开页面的规则：

- 编辑中保存：服务端返回 **`403 SHARE_REVOKED`**，**不是 412**——412 的语义是「版本冲突，可走差异面板」，无权限不能给用户「强制覆盖」的按钮；前端保留编辑器中的全部内容，并给「另存为我的笔记」一键转存，避免撤销动作变成内容丢失
- 只读浏览中：15 分钟缓存到期后页面转只读态并提示「共享已结束」；已在本地渲染的正文不做强制清屏（做不到，也不值得做）
- 撤销方与被撤销方都写一条审计日志（`share_id`、`action`、`actor`、`target`、`ts`），便于事后对账；**载体定稿（v1.13.3，K4）**：不落 S3，走函数既有 CloudWatch 日志组（`cloudjian-share-api-api`），单行 JSON 结构化输出，保留期沿用 12.7 的 **30 天**——零新增存储、零新增生命周期规则；检索用 CloudWatch Logs Insights 按 `share_id` 或 `actor` 过滤。若日后需要长期留存（>30 天），再单独评估落 S3 与生命周期标签，本期不做

**共享的展示形态（v1.10 定稿，原 17.1）**：别人共享给我的目录，在我侧边栏显示为**一条虚拟目录**（如「共享给我 / 项目A」），不是把内部几百篇笔记摊平成一堆散篇；点进去才展开其真实子结构。单篇共享则显示为一条独立笔记。

**展开的数据源（X7）**：虚拟目录节点由 `_share_inbox.parquet` 里的目录级共享记录渲染（owner uuid + `category_path`）；点进去时，服务端用该记录向 owner 的 `index.parquet` 按 `category_path` 前缀过滤、分页返回（**定稿选「直接读 owner 索引」，Y6**）：Lambda 执行角色本就有整个数据桶 `users/*` 的读权限，不需要为共享再授予任何跨用户路径，也不需要维护一份会过期的轻量清单；结果按「owner + category_path」缓存 15 分钟。**不在读取侧遍历 owner 的 `shares/`，也不做全库 LIST**。理由：目录共享在存储上本就是一条记录（7.2 不展开），展示成一个节点与存储模型一致，也不污染我的私有目录树。

为避免每次访问都逐级读多个 `.dir_meta.json`，登录时（或目录树变更后）由 Lambda 预计算一次「用户对每个可见目录的有效权限」，结果随会话缓存 15 分钟；访问笔记只查这份预计算结果，不再逐级 GET。

### 7.4 操作边界

被共享者即使拿到 `edit` 权限：

- 不能修改目录共享设置
- 不能删除根共享目录本身
- 不能把笔记移出共享范围
- 在共享目录内**新建/编辑笔记**自动继承当前目录权限；**新建子目录不在 `edit` 权限内**（写 `.dir_meta.json` 未列入 K3 的六处写白名单，v1.13.5 P-A）
- **版本历史边界（v1.13.2，T-02）**：`read` 可查看版本列表并与当前版本做对比，**不可回滚**；`edit` 可回滚（回滚同样先留存当前版本，6.4 的规则不变）；删除/永久清除版本一律仅 owner 可做
- **跨用户写路径清单（v1.13.3 扩写，K3）**：`edit` 对被共享内容的一切写入，只允许落在 **owner 前缀**下的六处：① `notes/{category_path}/{slug}.md`（正文本身）；② `versions/{note_id}/{timestamp}.md`；③ `index.parquet`；④ `search/shard-{n}.json.gz`；⑤ `assets/_refs.json`（引用计数，按笔记前缀归属，见 8.3）；⑥ `assets/public|private/…` 的**新增上传**（插图随笔记前缀，见 8.2）。**除此之外一律无权写**：不能删除或批量切换 owner 前缀下的既有图片、不能写 `_share_inbox.parquet`、不能写 `.dir_meta.json`（首条已禁）
- **校验位置**：Lambda 执行角色虽拥有整桶权限，仍须在上述路径上做显式校验（`shares/` 记录有效 + `level=edit`），**不得因 IAM 允许就默认放行**
- **只读态的版本入口（v1.13.4，T-E）**：`read` 用户版本抽屉里**只渲染「对比」**，「回滚到该版本」按钮**不渲染**（不是置灰）——置灰会让人反复点击并误判为权限故障；`edit` 两个都显示。抽屉内也去掉「回滚」的二次确认弹窗，避免给无权限用户走一遍必失败的流程
- **共享已撤销**：写入不再返回 412，而是 `403 SHARE_REVOKED`（见 7.3）

### 7.5 冲突检测与差异对比

所有正文写入统一带条件头，不再「先比对再写」：

1. 前端保存时携带打开编辑时的 `ETag` 与 `version`
2. Lambda 直接发起 `PutObject` 并附 `If-Match: <ETag>`
3. **200 成功** → 正常写入，`version` 自增
4. **412 冲突** → Lambda 读取服务端最新内容，生成差异，返回 412，按 9.4 的统一信封承载：`{code: "NOTE_CONFLICT", params: {note_id}, data: {...}}`，`data` 内含四份数据：
   - 服务端最新内容与最新 `ETag`
   - 用户本次提交内容
   - 行级差异结构（新增行 / 删除行 / 修改行）
   - 服务端最新 `version`
5. 前端弹出对比面板，用户选择处理方式
6. 用户确认「强制覆盖」时，用最新 `ETag` 重发写入；服务端旧版本已在第 2 步前存入 `versions/`

差异生成实现：

- 后端用 Python 标准库 `difflib`，行级 `unified_diff` 转结构化数组；零依赖、毫秒级
- 前端用 `react-diff-view` 渲染，默认左右分屏，支持行内合并视图
- 支持行级 + 字符级双重高亮
- 同一组件复用到「历史版本与当前版本对比」

| 选项 | 行为 |
|---|---|
| 强制覆盖 | 用我的版本覆盖服务端（基于最新 ETag），旧服务端版本已在 `versions/` 可找回 |
| 放弃我的修改 | 加载服务端最新内容到编辑器 |
| 手动合并 | 关闭面板，参考差异自行修改后重新提交 |

### 7.6 明确不做实时协同

真正的多人同时编辑（实时光标、实时同步）需要 AppSync WebSocket + CRDT/OT + DynamoDB 中间态，会推翻「纯 S3 + Lambda」的架构基调。本期不做。

---

## 8. 图床设计

### 8.1 笔记可见性与图片跟随（v1.13.7 重做）

**核心规则：图片没有独立可见性，完全跟随所属笔记。** 原设计让用户逐张设置「公开 / 仅登录可见」，与笔记的共享范围形成两套真源，必然出现两种坏组合——笔记私有但图片走 CDN 公开（正文受保护、附件却全网可读），笔记公开但图片私有（公开页整页裂图）。两套都不可接受，故废除单图可见性。

**笔记可见性档位（新增）**

| 档位 | 谁能读 | 存储/链接 |
|---|---|---|
| `private`（默认） | owner 本人 + 已共享成员（read/edit，按 7.2/7.3） | `GET /notes/{note_id}` 需登录；图片走预签名 |
| `public` | 任何持公开链接的人（匿名、无需登录） | `GET /public/notes/{public_token}`；图片走 CDN 直链 |

- `public_token` 为随机 22 位字符串，映射对象 `users/{uuid}/public_tokens/{token}.json` 存 `{note_id, created_at}`；**切回私有即删除该对象**，链接立即失效（旧 token 不再可解析），重新公开生成新 token，不复用旧链接。
- 公开是只读：匿名侧不可写、不可列目录、不可搜索、不可看共享成员；返回内容只有该篇的标题、正文、更新时间与图片直链，不含 `category_path` 之外的任何结构信息。
- 公开笔记对 owner 与已共享成员仍是普通笔记（可编辑）；编辑后匿名读者看到的即最新版本，不做版本发布流程。

**图片前缀由引用关系派生（公开优先）**

```
users/{uuid}/assets/
├── public/{note_id}/{asset_id}/{file}    # 被至少一篇公开笔记引用 → CloudFront 匿名可访问
└── private/{note_id}/{asset_id}/{file}   # 仅被私有笔记引用 → S3 预签名直连，TTL 5 分钟
```

一张图片可被多篇笔记引用（8.3 的 `_refs.json`、P-07「被 N 篇笔记引用」），所以可见性取**引用者中「最宽」的一档**：只要有一篇公开笔记引用它，该图就必须匿名可读，否则公开页会裂图。由此带来一个必须写明的后果：**同一张图若同时被公开笔记与私有笔记引用，它在私有笔记里也不再受保护**——只是 URL 需要被知道。UI 在公开前要提示「该图同时被 N 篇笔记引用」（P-26）。

**切换可见性 = 异步迁移 job**

- 入口：`POST /notes/{note_id}/visibility`（body `{visibility}`）→ 202 `{job_id}`；仅 owner 本人，grantee 一律 403。
- job 类型 `visibility_migrate`：重算该笔记引用的每个 asset 的派生可见性 → 需要变更的走 `public/` ↔ `private/` 的 Copy + Delete（`TaggingDirective=REPLACE`，标签语义与 8.3 的 30 天规则一致，不得把 `cj:retention` 带进正式前缀）→ 改写正文中的图片链接形态（公开图写 CDN 路径、私有图写 `asset://{asset_id}` 占位）→ 重建该笔记所在搜索分片 → 对旧的公开路径做 CloudFront 失效。
- 幂等与续跑：`cursor` 记录已迁移的 asset_id；重复执行只补未完成项，Copy 可重入、Delete 幂等；item 失败进 `failed[]`，job 结束为 `partial` 并提示重试，不整篇回滚（回滚会把已改写的链接再改回去，成本更高）。
- 与 purge / restore 互斥：同一 `user + root` 只允许一个 job，冲突 409 `JOB_RUNNING`（沿用 6.1 与 9.3.1 的规则）。

**团队开关（原 17.5 改造，不再是图片级）**

| 配置 | 作用 | 违规表现 |
|---|---|---|
| `default_note_visibility` | 新用户初始默认 & 新建笔记默认档位（`private` / `public`）；**只改默认值**，不动既有笔记，切换不触发迁移 | 无 |
| `force_private` | 开启时禁止把任何笔记设为公开 | `POST /notes/{note_id}/visibility → public` 返回 400 `NOTE_VISIBILITY_FORBIDDEN`；只拒绝、不静默改写 |

配置仍存 `users/_team_config.json`（5 分钟内存缓存 + `If-None-Match`），读取侧不再在 presign 阶段做可见性判断——presign 拿不到用户意图，判断位置改到「设置笔记可见性」这一步才是对的。

**为什么私有图仍走 S3 预签名而不是 CloudFront 签名 URL**（结论不变，理由见 8.4 前的说明）：预签名与签名 URL 同属 bearer 链接，持链接即可见；TTL 压到 5 分钟后语义等价，而组件少一整套（无需 Trusted Key Group / 私钥轮换 / KVS）。公开笔记的图片走 CDN，因为它本来就该被匿名读。

### 8.2 上传流程

1. 用户在编辑器粘贴或拖拽图片。**不再选择可见性**（v1.13.7）：前缀由所在笔记当前的 `visibility` 决定，UI 只显示「随笔记可见（当前：公开/私有）」
2. 前端请求 `POST /assets/presign` 生成 S3 预签名 URL，请求体含 `note_id`、`content_type`、`size`（**v1.13.7 删除 `visibility` 参数**）。**目标前缀由 note 归属决定**（v1.13.3，K3）：自己的笔记 → 自己的 `assets/`；共享笔记且请求者对该 note 有 `edit` → **笔记所属者前缀的 `assets/`**；其余一律 403。同时锁定 Content-Type。**团队「强制私有」不在此处校验**（v1.13.7 改位置）：强制私有作用于「把笔记设为公开」这一步，见 8.1；presign 只按笔记现有 `visibility` 决定前缀，命中 `public/` 说明笔记已是公开笔记，属既有状态而非新决策
   - **大小上限无法靠 PUT 在服务端强制（F11）**：`content-length-range` 只存在于 POST policy。两条可选路线：①改用**预签名 POST**（`create_presigned_post` + `content-length-range`，可硬限 10MB，代价是前端改 `multipart/form-data` 上传）；②仍用 PUT，前端限大小 + Lambda 登记时校验 `HeadObject` 的 `ContentLength`、超限即删除并报错
   - 本项目默认走 **② + 登记校验**：实现简单、路径不变；不足是「超大文件会先落盘再被删」，成本可忽略（生命周期 1 天内清掉孤儿），但**不能声称服务端已强制限流**。**v1.13.2 定稿（T-05）：维持②，不改预签名 POST**（改 POST 要重写前端上传为 `multipart/form-data`，收益只是把「先落盘再删」变成「直接拒绝」，不值得为它引入一条新链路）；10MB 由**前端选文件时前置校验 + 登记时 `HeadObject` 的 `ContentLength` 二次校验**，UI 文案写「单张 10MB 上限」，不写「服务端强制限制」
   - **图片随笔记前缀（v1.13.3，K3 定稿）**：共享目录里插图，必须落到**笔记所属者**的前缀，而不是插图者的前缀。理由：`_refs.json` 按前缀维护、删除/恢复联动也按前缀执行，图与笔记同属一个 owner 才能让「引用计数 → 换签校验 → 回收站清理」整条链只在单前缀内闭合；否则「B 在 A 的共享目录新建笔记并插图」会让 owner 的 `_refs.json` 永远查不到 B 的图，换签必然失败（裂图），且没有任何机制能补上这份跨用户计数。代价需写明：**插图存储与配额计在笔记所属者头上**；插图者的图片管理面板（8.4）只列自己前缀，不会显示这张图；被共享者只能**新增与登记**图，不能删除或批量切换 owner 前缀下的既有图片。这条跨前缀写权限一并列入 7.4；编辑器在共享笔记内**首次**插图时给一行轻提示「图片存储计入笔记所有者」（v1.13.4，T-D），每个会话只提示一次、不阻断操作
3. 前端直传 S3，不经过 Lambda。**桶级 CORS 必须配置**（P1-4）：`AllowedOrigins` 为 CDN 域名，`AllowedMethods=[GET,PUT]`，`AllowedHeaders=[content-type]`，`ExposeHeaders=[ETag]` —— 前端 PUT 后要读 ETag 回传 Lambda 登记，缺 `ExposeHeaders` 会导致登记失败；canvas 缩略图也依赖 GET 的 CORS
4. 上传成功后前端在光标处插入 Markdown 图片链接：**公开笔记**写 CDN 路径（`https://<cf-domain>/users/{uuid}/assets/public/{note_id}/{asset_id}/{file}`），**私有笔记**写 `asset://{asset_id}` 占位，渲染时向 Lambda 换预签名 URL（v1.13.7：形态由笔记可见性决定，不由单图决定）
4b. **公开图经 CloudFront 时的 CORS（F7）**：桶级 CORS 只覆盖直连 S3 的路径，公开图走 CDN。若公开图 Behavior 的缓存策略不把 `Origin` 放进缓存键，首个无 Origin 的响应会把「无 ACAO」缓存下来，之后带 Origin 的 canvas 请求读到无 ACAO 的缓存副本 → 画布污染、间歇性失败。处理：公开图 Behavior 的缓存策略**转发 `Origin` 并进入缓存键**（`headers_config` 含 `Origin`）；CI 用带 `Origin` 头请求公开图两次（冷/热缓存）各断言一次 ACAO 存在
5. 切换笔记可见性：`POST /notes/{note_id}/visibility` → `visibility_migrate` job（见 8.1），由 job 完成前缀迁移、链接改写与 CDN 失效；**不提供「单张图切换」接口**（v1.13.7 删除）

### 8.3 反向引用表（补 v1.0 缺口）

v1.0 的「该图片仍被 N 篇笔记引用」需要全量扫描所有 md，无法在线实现。本版增加反向引用：

- 每个用户前缀维护 `assets/_refs.json`（图片 asset_id → 引用它的 note_id 列表）
- **归属规则（v1.13.3，K3）**：`_refs.json` 属于**笔记所在的前缀**，不是插图者的前缀。共享目录里由他人新建/编辑的笔记，其插图已随笔记落进 owner 前缀（8.2），引用计数自然也记在 owner 的 `_refs.json`；共享编辑者保存时对这份文件做条件写（与 7.4 的第⑤项对应）。这样「引用计数 → 换签校验（8.1）→ 删笔记迁图 → 恢复迁回」全程在单前缀内闭合，既不跨用户查表，也不新增反向索引
- 笔记保存时增量更新（若图片被新增/删除引用），同样用条件写
- 删除图片仅告警不阻断，被引用的图片标记 `orphan=false` 并保留
- **删除笔记时联动清理随笔记可见的图片（v1.10.1 修正，原 17.4 的落地方式）**：删除笔记时读 `_refs.json`，把**仅被该笔记引用**的图片从 `assets/public/` 或 `assets/private/` 移到 `assets/_trash/{asset_id}/{file}` 并打 `cj:retention=30d`，与笔记同生命周期；30 天后由已有标签规则物理删除。恢复笔记（单篇或目录级）时**同步把对应图片移回原前缀（按恢复后笔记的 `visibility` 重新落位）并去掉标签**，D2 的目录恢复因此完整。
  - **为什么不再「立即物理删除 + 判定无其他引用」（X4）**：`_refs.json` 是**每前缀**的，外部链接与其他前缀的引用根本不在里面（7.2 已禁全库 LIST，`_share_inbox.parquet` 也不含图片反查），「再无其他引用」没有数据源；公开图语义本就是持链接即可访问，用「无引用才删」约束它逻辑不成立；且软删除后 30 天内可恢复，立即物理删图会摧毁恢复能力、目录级恢复更会整目录图片全失效。改为「移入 `assets/_trash/` + 30 天」后，清理意图保留、判定退化为本用户 `_refs.json` 的确定事实、恢复链完整，零新增机制。
  - 私有图孤儿同样覆盖（X18）：`assets/private/` 中失去引用的对象一并移入 `assets/_trash/`，与公开侧同一规则，不再长期滞留。
  - **引用变化要重算可见性（v1.13.7）**：保存笔记后若 `_refs.json` 的引用集合发生变化，需按 8.1 的「公开优先」规则重算受影响 asset 的派生可见性；出现「公开 → 私有」的降级时必须走 `visibility_migrate` 的迁移步骤（Copy 回 `private/` 并做 CDN 失效），不能只改元数据，否则旧 CDN 链接仍可访问。保存主流程只记录待迁移集合，迁移交给 job，避免把 25 秒预算耗在保存上。
  - **彻底删除时的图片边界（v1.13.6）**：回收站 purge 读同一份 `_refs.json`，只物理删除 `ref_count` 归零的 `assets/_trash/{asset_id}/`；仍被其他笔记引用的图片只清本笔记的引用条目、对象保留。这样一次 purge 不会弄裂别人的笔记，也无需引入「全站引用」这种没有数据源的判定（8.4 同一取舍）。

### 8.4 图片管理面板

- 调用 Lambda 列出 `assets/` 下所有图片（缩略预览、大小、上传时间、派生可见性、被引用数）
- 支持插入到光标处、删除；**不提供切换可见性**（v1.13.7）：面板只读展示「可见性：随笔记（公开/私有）」与「被 N 篇笔记引用（其中 M 篇为公开笔记）」，并给一行提示「想让这张图公开，请把笔记设为公开」
- **「被引用数」口径（v1.13.4，T-C）**：按 asset 汇总**当前前缀内** `_refs.json` 里指向它的 `note_id` 条数（同一篇重复引用只算一次）；公开与私有同口径、不分开统计；**不含跨前缀与外部链接**——这部分没有数据源（7.2 已禁全库 LIST）。所以 UI 文案写「被 N 篇笔记引用」，不写「被引用 N 次」；删除时的告警也用同一口径，不做「全站引用」这种无法兑现的承诺
- 不做自动压缩与缩略图存储，缩略预览用前端 canvas 生成

---

## 9. 国际化与多语言

### 9.1 语言范围与策略

| 语言 | 代码 | 状态 |
|---|---|---|
| 简体中文 | `zh-CN` | 默认语言、基准语言（所有 key 的源头） |
| English | `en-US` | 完整支持 |
| 日本語 | `ja-JP` | 完整支持 |
| 其他 | — | **本期不做**（X10）：三语封版，不预留第四语言；新增语言属未来变更，需单独评审） |

策略要点：

- **界面全量翻译**，**内容不翻译**。笔记正文是用户资产，不做机器翻译，也不存多语言副本
- 基准语言固定 `zh-CN`：所有新增文案先写中文，再补英日；缺失翻译时回退到 `zh-CN` 而不是显示 key
- 只有三种语言，不引入异步按需加载，语言包随主包一起打包（总增量约 30–60KB）

### 9.2 前端实现

- 库：`react-i18next` + `i18next` + `i18next-browser-languagedetector`
- 命名空间拆分：`common`（通用按钮/状态）、`editor`、`notes`、`share`、`admin`、`errors`、`auth`
- 目录结构：

```
frontend/src/locales/
├── zh-CN/{common,editor,notes,share,admin,errors,auth}.json
├── en-US/…
└── ja-JP/…
```

- key 命名：`模块.组件.语义`，如 `notes.list.empty`、`editor.toolbar.modeSplit`；不写序号、不写中文
- 插值与复数走 i18next 内置能力（`{{count}}`、`_one` / `_other`），不用字符串拼接
- 带富文本的句子用 `<Trans>` 组件，避免把标签拆成碎片 key

### 9.3 语言选择与持久化

优先级从高到低：

1. 用户显式选择，存 `profile.json` 的 `ui_lang`，登录后从 S3 读取 → 跨设备一致。**`profile.json` 是语言偏好的唯一真源**，注册表不再保留 `pref_lang` 镜像，避免同一数据两处存放
2. 本地缓存 `localStorage['cj:lang']`（未登录或首次加载时用，避免闪烁）
3. 浏览器 `navigator.language` 推断（`zh*` → zh-CN，`en*` → en-US，`ja*` → ja-JP）
4. 默认 `zh-CN`

交互要求：

- 切换入口在右上角用户菜单，切换后**即时生效不刷新页面**（i18next `changeLanguage` + React 重渲染）
- 切换时同步写 `profile.json`（失败不阻断，仅本地生效并在下次登录重试）
- 登录页本身也支持三语切换（未登录时用 localStorage 的偏好）
- 首屏语言在 `index.html` 渲染前由内联脚本读取，避免中文闪一下再切英文

### 9.4 后端与错误码

- **Lambda 不返回任何自然语言文案**，统一返回 `{ code, params }`，如 `{ "code": "NOTE_NOT_FOUND", "params": { "id": "01JC..." } }`
- 前端在 `errors` 命名空间按 code 查翻译并插值，未知 code 回退 `errors.unknown` 并附 code 原文便于排查
- 错误码是接口契约的一部分，新增错误码必须同步提交三份语言包（CI 校验，见 9.7）
- **统一错误信封（v1.13.2，T-01）**：所有非 2xx 响应一律为 `{ "code": "...", "params": {...}, "data": {...}? }`，`data` 只用于必须携带结构化上下文的场景。据此消解三处口径冲突：
  - 7.5 的 412 不再「裸返四份数据」，而是 `{ "code": "NOTE_CONFLICT", "params": { "note_id": "..." }, "data": { "server_content", "server_etag", "client_content", "diff", "server_version" } }`
  - 5.3.5 的 409 → `{ "code": "DELETE_CONFLICT", "params": { "note_id": "..." } }`
  - 6.1 的搬移只读态 → `{ "code": "JOB_RUNNING", "params": { "job_id": "...", "progress": 0.42 } }`
  - 这样前端拦截器只有一条判断链（`401` 跳登录 / `403 SHARE_REVOKED` 转存 / `412` 进差异面板 / `409` 提示 / 其余按 code 查文案），不会出现「412 走一套、其余走另一套」的双分支
- **错误码表（v1.13.2，T-01）**：`backend/app/errors/error_codes.py` 是唯一真源（13.3 已列该模块），实现前先产出全表，每行含 `code` / HTTP 状态 / `params` 契约 / 三语 key。**冻结门项（v1.13.4，T-A）**：整表随首个业务接口的 PR 一并冻结，评审通过后**只增不改**；新增一行必须同时带 HTTP 状态与 `params` 契约，缺任一项 CI 直接失败，避免出现「码有了、参数没约定」的半成品。最小覆盖组：`AUTH_*`（含 `SHARE_REVOKED`、`TOKEN_EXPIRED`）、`NOTE_*`、`DIR_*`、`SHARE_*`、`ASSET_*`、`EXPORT_*`、`JOB_*`、`USER_*`、`INTERNAL_ERROR`。前端 `errors.code.*` 由脚本从该文件生成，**禁止手写**，这是「新增码必同步三语」唯一能自动化的实现方式
- **错误码 → 语言包 key 的派生规则（v1.13.2，T-12）**：统一 `errors.code.<code 小写蛇形>`，例如 `NOTE_NOT_FOUND` → `errors.code.note_not_found`。仍满足 9.2 的 `模块.组件.语义` 三段式（模块 `errors` / 组件 `code` / 语义为码名）；不采用 `errors.NOTE_NOT_FOUND` 这种大写 key，既与 9.2 的语义化惯例不符，也不好被 i18next-parser 扫描
- 412 / 409 / 403 属正常业务分支，**不计入 5xx 错误率告警口径**（12.7 只告警 Lambda 异常与 5xx），但 `JOB_RUNNING` 与 `SHARE_REVOKED` 要打独立计数指标，便于发现任务卡死与权限抖动
- 后端日志、代码注释、Terraform 变量说明统一用英文，避免日志中出现多语言混杂

### 9.5 编辑器与第三方组件

- Vditor 支持 `lang` 配置项，按当前界面语言传 `zh_CN` / `en_US` / `ja_JP`，编辑器内置提示（如「上传中」）随语言切换
- 代码高亮的语言名、Mermaid 语法关键字保持英文，不做翻译
- 日期选择器、下拉框等第三方组件的 locale 由统一入口注入，避免各组件自己判断语言

### 9.6 日期、数字、时区

- 存储一律 UTC 毫秒时间戳（int64），前端不存本地时间字符串
- 展示用 `Intl.DateTimeFormat(locale, { timeZone })`，时区取 `profile.json` 的 `tz`（默认取浏览器时区）
- 相对时间（「3 分钟前」）用 `Intl.RelativeTimeFormat`，不手写拼接
- 文件大小、数字千分位用 `Intl.NumberFormat`；存储容量单位统一 KB/MB/GB，不按语言改单位制
- 笔记 Frontmatter 的 `created_at` 落盘用 ISO8601 + 偏移（如 `2026-11-25T10:00:00+08:00`），便于人工排查
- **排序规则（v1.13.4，T-F）**：标题与目录树排序统一走 `Intl.Collator(locale)`（中文按拼音、日文按假名、英文忽略大小写并忽略变音符号）。该规则 v1.13.2 已写在 9.7「排序规则」一行，本节补交叉引用，**只允许一个实现口径**，不许两处各写一套

### 9.7 工程保障

| 保障项 | 做法 |
|---|---|
| key 完整性 | CI 脚本以 `zh-CN` 为基准，比对三语 key 集合，缺失即失败 |
| key 格式（v1.13.2，T-12） | 正则校验 `^(common\|editor\|notes\|share\|admin\|errors\|auth)\.[a-z0-9_]+(\.[a-z0-9_]+)+$`；`errors.code.*` 另做双向校验——`error_codes.py` 里每个 code 必须有 key、语言包里每个 `errors.code.*` 必须在码表登记，任一方向缺失即失败，防止出现「有码无文案」与「有文案无码」 |
| 禁止硬编码 | ESLint 规则拦截 JSX 中的中文字面量，必须走 `t()`；白名单例外：Vditor 内置提示、Mermaid 语法关键字、测试快照 |
| 未使用 key | 定期跑 i18next-parser 扫描，清理孤儿 key |
| 文案长度 | 日/英文案普遍比中文长 20–60%，按钮用最小宽度 + 自适应，不写死 pixel 宽度 |
| 视觉回归 | 三语各截关键页面（登录、列表、编辑器、管理后台），对比排版是否错位 |
| 排序规则 | 列表按标题排序时用 `Intl.Collator(locale)`，中文按拼音、日文按假名 |

### 9.8 笔记语言标注与检索

- 新建笔记时 `lang` 字段默认取当前界面语言，用户可在属性面板修改
- `lang` 用于搜索排序加权（同语言结果优先）与未来的拼写检查入口，本期不做翻译
- 导出的 `.md` 文件名保持原文，不因界面语言改写
- 分享给其他语言用户时，正文原样传递，界面 chrome 按接收者语言渲染

### 9.9 明确不做

- 不做笔记正文机器翻译（成本与准确性都不划算，且会破坏 Markdown 结构）
- 不做 RTL 布局（当前无阿拉伯语/希伯来语需求）
- 不做后端多语言邮件/通知模板（本期无邮件通知能力）
- 不做语言级权限（不限制某用户只能用某语言）
- **不做第四种语言**（`ko-KR` 等不进入本期范围）
- **不做语言级内容规范**：不强制日文笔记标 `ja-JP`、不校验正文语言与 `lang` 是否一致，`lang` 仅作检索提示

---

## 10. 前端设计要点

- 路由：`/login`、`/notes`、`/admin`（非管理员访问自动重定向）；React Router 用 `basename="/"`，构建产物 `base` 指向 `/web/`，CDN 上由 Function rewrite 把 `/`、`/login`、`/notes`、`/admin` 映射到 `/web/index.html`，两者必须一致（P0-3）
- 布局：左侧目录树 + 中间编辑区 + 右侧图片库/版本历史抽屉
- 主题：暗色默认，light/dark 切换，配置存 `profile.json`
- 编辑器：Vditor 三模式按钮切换，代码高亮覆盖主流语言，Mermaid 渲染
- 登录态：AccessToken / IdToken 均 20 小时，请求拦截器注入 AccessToken；**跳登录有两条触发路径**（G2）：① 本地解析 AccessToken 的 `exp`，过期即跳（正常路径）；② 收到 401 或 `fetch` 抛 CORS/network error 且本地 `exp` 已过即跳（兜底，防网关 401 不带 ACAO 时读不到 status）；412 统一进冲突面板
- 国际化：见第 9 章，`t()` 全量覆盖，语言切换即时生效
- 长列表虚拟滚动（> 200 条），避免渲染卡顿
- **会话到期保护（v1.13.2，T-09，列 P1）**：AccessToken 20 小时硬到期、且不使用 Refresh Token，「正在写」必然至少撞上一次到期，这不是边缘场景。四条一起做：
  1. 解析 `exp`，剩余 **10 分钟**起在顶栏常驻提示「会话将在 N 分钟后结束，请及时保存」，不弹模态（打断写作）
  2. 编辑器输入 **debounce 5 秒**写 localStorage 草稿，键 `cj:draft:{note_id}`，值含 `content` / `base_version` / `base_etag` / `updated_at`；只保留最近一篇、上限 256KB，超出即放弃写入并提示
  3. 重新登录后若有草稿：`base_version` 与服务端一致 → 直接回填并提示「已恢复未保存的内容」；不一致 → 装载草稿并走 7.5 差异面板，**不静默覆盖**
  4. 保存成功或用户显式「放弃草稿」后清除；不把草稿写进 S3（避免与正文版本混淆）
- **云端偏好与本地偏好的分界（v1.13.2，T-11）**：`profile.json` 只存跨设备需要同步的 6 项（`ui_lang` / `tz` / `theme` / `editor_mode` / `list_sort` / `page_size`）；目录树展开状态、面板宽度、滚动位置等高频琐碎状态走 localStorage，不进 `profile.json`——后者每写一次就产生一个 S3 版本，把 UI 状态塞进去等于白送 Versioning 与 PUT 成本（12.7 的非当前版本清理规则正是为此存在）
- **到期横幅的形态（v1.13.4，T-G）**：文案 key `common.session.expiryWarning`，中文「会话将在 {{count}} 分钟后结束，请及时保存」、英文 "Your session ends in {{count}} min — save now."、日文「セッションはあと {{count}} 分で終了します。保存してください」。单行、**不弹模态**、只给一个「立即保存」按钮，**不给「续期」**（没有 Refresh Token，续不了就别画这个按钮）。日/英普遍比中文长 40% 以上：横幅用弹性宽度 + 单行省略，**不写死 pixel**（与 9.7 的「文案长度」一条同源）
- **离线编辑（v1.13.4，T-H，本期不做；产品已确认）**：不做离线编辑、不做离线写队列。断网时的行为定死：编辑器转只读、顶部提示「网络已断开，内容仍保存在本地草稿」，本地草稿照常按 T-09 的 debounce 写 localStorage；恢复网络后按 `base_version` 决定「直接回填」还是「走差异面板」。离线期间保存、搜索、导出、换签等 API 动作一律明确失败并给 `NETWORK_OFFLINE` 文案，**不做乐观假保存**——假装成功是这类产品最伤信任的失败模式。真离线编辑（本地 CRDT + 重连合并）属单独立项，不混进本期

---

## 11. 安全隔离设计

单桶本身不构成风险，风险在于「把 Cache Behavior 当成访问控制」。本版按审核 R1 重写。

### 第一层：CloudFront 路径白名单（三道闸）

**闸 1 · Bucket Policy 精确到前缀**

OAC 的授权 `Resource` 不再写整桶 `arn:aws:s3:::bucket/*`，而是精确两条：

```
arn:aws:s3:::cloudjian-data-tokyo/web/*
arn:aws:s3:::cloudjian-data-tokyo/users/*/assets/public/*
```

`Condition` 仍限定 `AWS:SourceArn` 为本分发的 ARN（从 SSM `/cloudjian/cdn-arn` 注入，禁止写死）。其余前缀对该分发**无读权限**，即使路径被命中也会被 S3 拒绝。

**闸 2 · CloudFront Function 白名单**

分发必须有默认 Behavior（`*`），这是绕不过去的。因此在 viewer-request 阶段挂一个 CloudFront Function：

```
放行：/web/*                                  → 原样回源（.js/.css/.png 等真实文件）
放行：/users/{uuid}/assets/public/*           → 原样回源
拒绝：/users/* 其余、index.parquet、.dir_meta.json、assets/private/* → 403（终态响应，不回源）
重写：其余「无扩展名」路径（/、/login、/notes、/admin、任意深链）→ /web/index.html（200）
不重写：/web/ 下带扩展名但实际不存在的文件（如 /web/missing.js）→ 交源站返回 404
```

默认 Behavior 指向 S3 源站，但命中私有路径时函数先返回 403，请求根本不会回源。

> SPA 路由（P0-3 / F2）：`DefaultRootObject` 在 Function 已生成响应时不起作用，所以 `/` 必须在 Function 里显式 rewrite 到 `/web/index.html`。**深链兜底也放在函数里（catch-all rewrite），不使用分发的 `CustomErrorResponses` 403→200** —— 这两个机制互斥：前者把函数 403 当最终响应直出，后者会把合法 403 也改写成 200 HTML，两者同时配一定坏一边（要么深链白屏，要么闸 3 的 403 断言永远失败）。因此：私有路径恒 403（终态，不经错误页）、无扩展名深链恒 200、`/web/*` 真实文件缺失时如实 404。分发上不配置任何 403/404 映射。

> 注意：`assets/private/*` **本来就不在 CDN 上提供服务**，其访问走 S3 预签名 URL 直连（见 8.1）。因此白名单在此处不是「堵住」而是「本来就不存在入口」，不存在与私有图功能冲突的问题。

**闸 3 · CI 匿名穿透测试**

流水线中加入一组真实 key 的匿名请求用例（用真实 `sub`、真实笔记路径、真实 `index.parquet`、`.dir_meta.json`、`assets/private/*`），断言全部 `403`。任一用例返回 200 即阻断发布。

> 备选方案（更不易错，但偏离单桶）：把公开内容拆到独立桶。若后续运维压力大，可平滑切换——前端路径不变，只改第二个 Origin。

### 第二层：API 鉴权与越权防护

- 所有私有数据只能通过 Lambda 获取，前端永不直接读 S3
- 每个请求验 Token → 解析 `sub` → S3 路径强制拼接该 `sub` 前缀
- 路径参数统一规范化（消解 `../`、URL 编码回溯），校验最终路径落在允许命名空间内
- 跨用户访问只能通过 `shares/` 链路，逐级校验权限，无权限直接 403，不发起 S3 读
- 角色判断以注册表为准，不信任 Token 内的 groups

### 第三层：返回数据最小化

- 前端拿不到完整 `index.parquet`，只拿当前请求的分页结果
- 查看共享笔记只返回该篇元数据，不返回对方整份索引
- `.dir_meta.json` 只返回共享相关必要字段
- 搜索只返回命中分页与短摘要，不下发全量正文

### 增强项

- **CloudTrail 只开管理事件**（免费）；数据事件按需临时开启并按前缀过滤，避免账单翻倍（见 12.9）
- S3 Server Access Logging（本身免费，只付日志对象存储），保留 30 天

---

## 12. 部署与运维（三工程分离）

### 12.1 工程划分与边界

云笺拆为三个独立 GitHub 仓库、三条独立流水线，各自只做一件事，互不越界。

| 工程 | 仓库 | 只负责 | 明确不做 | 部署目标 |
|---|---|---|---|---|
| 前端工程 | `cloudjian-frontend` | React 构建产物发布到 S3 `web/` 前缀、CloudFront 缓存失效 | 不创建任何 AWS 资源、不碰 Lambda、不改 IAM、不改桶策略 | S3 + CloudFront |
| 后端工程 | `cloudjian-backend` | **Lambda 全生命周期**：创建/更新函数、Parquet Layer、别名切换、API Gateway 集成授权、冒烟测试与回滚 | 不改桶策略、不改 OIDC 角色、不建分发、不改 API Gateway 路由结构 | Lambda 函数、Layer、别名 |
| 基础设施工程 | `cloudjian-infra` | 全部基础设施的 Terraform 编排：S3 桶（含生命周期、Bucket Policy、OAC、**CORS**）、CloudFront、CloudFront Function、Cognito、API Gateway（**HTTP API**）路由与 Stage、EventBridge Scheduler（只建调度、目标为固定命名的函数 ARN）、IAM（含 Lambda 执行角色）、SSM 参数、日志与告警、Budgets | **不创建、不更新任何 Lambda 函数与 Layer，也不部署任何 VPC 网络资源**；不打业务代码包、不 `s3 sync` 前端产物 | 除 Lambda 与网络外的全部基础设施 |

分离的核心收益：三条流水线互不阻塞（改一个按钮不需要重跑 Terraform）、权限可收到最小、任一工程出问题能独立回滚。

**API 网关选型：HTTP API（v1.8 决策）**

| 维度 | REST API（v1.7.1 及以前） | HTTP API（现方案） |
|---|---|---|
| 请求费 | $3.50/百万 | **$1.00/百万**（A/B/C 档按 6.6 万 / 13.2 万 / **26.4 万**次计为 $0.07 / $0.13 / **$0.26**） |
| 集成方式 | Lambda 代理集成 + 资源树 | 路由键（`GET /notes`、`PUT /notes/{id}`）+ Lambda 代理集成，路由更扁平 |
| 集成超时 | 29 秒 | 30 秒（Lambda 仍设 25 秒，留 5 秒余量） |
| 负载上限 | 10MB | 10MB（口径不变，6.3/6.6 的规避设计无需改） |
| 鉴权 | Cognito 授权器 / Lambda 授权器 | **双层**：HTTP API 原生 JWT 授权器做网关前置过滤（验签、`iss`、受众、`exp`）+ Lambda 中间件（`token_use`、注册表 `status`/`role`、`auth_time`）。两者是叠加关系，不是二选一 —— 详见本节「网关鉴权」 |
| 丢失的能力 | —— | API Key、Usage Plan、网关缓存、WAF、请求校验器、REST 的响应流式传输 |

未用任何 REST 独有能力（无 API Key、无 Usage Plan、无网关缓存、无 WAF、无请求校验器、无流式响应），且导出已改预签名直下 S3，因此切换是纯降价，无功能回退。

HTTP API 的 8 组路由（路由键，全部走 Lambda 代理集成，stage `dev`）：

| 路由键 | 目标函数 | 说明 |
|---|---|---|
| `GET /notes`、`POST /notes` | `cloudjian-notes-api` | 列表分页 + 新建 |
| `GET/PUT/DELETE /notes/{note_id}`、**`POST /trash/purge`** | `cloudjian-notes-api` | 读取、`If-Match` 更新、软删除；**回收站彻底删除（单篇/批量/整目录/清空，202 + job）** |
| `GET /notes/{note_id}/versions`、`POST /notes/{note_id}/versions/{ts}/restore` | `cloudjian-notes-api` | 版本列表与回滚 |
| `POST /notes/{note_id}/visibility`、`GET /public/notes/{public_token}` | `cloudjian-notes-api` | 笔记可见性切换（仅 owner，202 + `visibility_migrate` job，见 8.1）；**公开笔记匿名只读**（无鉴权路由，持 token 即可读，只返回该篇内容与图片直链） |
| `GET /search`、`GET /dirs`、`POST /dirs/move` | `cloudjian-notes-api` | 搜索、目录树、可续跑搬移 |
| `GET/POST/DELETE /shares` | `cloudjian-share-api` | 共享授权与撤销 |
| `POST /assets/presign`、`POST /assets/register`、`GET /assets/{asset_id}/url`、`POST /assets/urls` | `cloudjian-asset-api` | 直传签名（`presign` 按**笔记当前可见性**决定 `public/` 或 `private/` 前缀、锁 Content-Type；不含可见性参数）、登记、**单张换签**（`GET …/url?note_id=…`）、**批量换签**（`POST /assets/urls`，body `{note_id, asset_ids[]}`，≤50 张） |
| `GET/POST/PATCH/DELETE /admin/users`、`POST /admin/users/{sub}/reset` | `cloudjian-admin-api` | 开号、禁用、调角色、重置密码 |
| `POST /exports`、`GET /exports/{job_id}` | `cloudjian-export-api` | 单篇/批量导出与任务查询 |

**网关鉴权：原生 JWT 授权器（v1.9）**

除 maintenance 外，上述路由统一挂一个 JWT 授权器：

| 配置项 | 值 | 说明 |
|---|---|---|
| Issuer | `https://cognito-idp.ap-northeast-1.amazonaws.com/<pool-id>` | 发错池/发错区的 Token 直接拒 |
| Audience | **App Client ID**（不是 User Pool ID） | Cognito AccessToken 没有 `aud`、只有 `client_id`，授权器在缺 `aud` 时回退校验 `client_id`；填错这里等于所有请求 401 |
| Identity source | `$request.header.Authorization` | 网关自动兼容 `Bearer ` 前缀，前端零改动 |
| 算法 | RSA（从 issuer 的 `jwks_uri` 取公钥） | 缓存最长 2 小时；Lambda 侧不做验签，因此不存在第二份 JWKS 缓存 |
| Scope | **暂不声明**，列为实测后的可选加固 | 云笺走 `USER_SRP_AUTH`，Cognito 直登签发的 AccessToken **默认带 `scope = aws.cognito.signin.user.admin`**（4.7 能用它调 `GlobalSignOut` 的前提），而 ID Token **没有 `scope`**。因此声明 `authorizationScopes = ["aws.cognito.signin.user.admin"]` 就能在网关直接拒掉 ID Token，**无需建 Resource Server、无需改发 token 流程、零费用**（G9）。先实测 SRP 返回的 scope 实际值再启用；代价是绑定 Cognito 内置 scope 语义，未来若改自定义 scope 需同步改造。启用后 `token_use` 由「唯一防线」降为「第二道防线」 |

**网关能拦**：签名/`kid`/算法、`iss`、受众、`exp`/`nbf`/`iat`。
**网关拦不住（必须留在 Lambda 中间件）**：账号禁用状态、改密后的旧 Token（`auth_time` vs `password_changed_at`）、`GlobalSignOut` 后仍有效的 JWT（离线验签看不见撤销）；以及 **`token_use`——仅在「未声明 scope」时拦不住**。一旦按 G9 给路由声明 `authorizationScopes`，ID Token 会因缺 `scope` 被网关直接拒，此时 `token_use` 由唯一防线降为第二道（V9）

> **ID Token 冒充是这里唯一的真风险**：Cognito 的 ID Token 的 `aud` 就是 App Client ID，签名、`iss`、受众全部合法，因此在**当前未声明 `authorizationScopes` 的配置下，拿 ID Token 也能过网关**（启用 scope 后 ID Token 会因缺 `scope` 被拒）。4.6 第 5 条的 `token_use=access` 检查因此是硬要求，不是可选项 —— 网关只是前置过滤，不能替代它。

**门禁分工**

- 5 个业务函数的中间件**直接使用 `event.requestContext.authorizer.jwt.claims`（方案 A：信任网关已验签）**，不做本地 JWKS 验签，再查注册表判 `status`/`role`、比 `auth_time`
- 为什么删掉「保留本地验签」：claims 是**已解码的集合**、不含原始 JWT，要本地验签必须从 `event.headers.authorization` 重取原始 Token（那是方案 B，每次多一次 JWKS 拉取与解码）。「省一次解码」与「仍做本地验签」互斥，本项目**明确选 A**
- A 的代价是「漏挂授权器的路由会裸奔」，因此兜底不靠运行时而靠 CI 门禁（下条）；同时中间件必须断言 `requestContext.authorizer` 存在，缺失直接 401

**路由挂载门禁（G4）**

- Terraform 里 8 组业务路由必须显式 `authorization_type = "JWT"`、`authorizer_id` 指向同一个授权器。**HTTP API 路由省略该字段时默认 `NONE`**，属高危默认值，不能靠人工检查
- infra 流水线执行 `apigatewayv2 get-routes`，逐条断言 8 组路由均为 `JWT` 且 `AuthorizerId` 等于 SSM `/cloudjian/jwt-authorizer-id`；唯一例外是显式声明的 `OPTIONS` 预检路由（`NONE`）
- `/cloudjian/jwt-authorizer-id` 由此获得**自动化消费者**：既是门禁的期望值来源，也是排障对照值（不再是「诊断用、无人读」）
- 可另接 AWS Config `API_GWV2_AUTHORIZATION_TYPE_CONFIGURED` 或 Checkov `CKV_AWS_309` 作为第二道视图
- `cloudjian-maintenance-api` **不挂 JWT 授权器、不暴露到 HTTP API**（它由 EventBridge Scheduler 用 `cloudjian-scheduler-role` 直调），避免出现「定时任务必须带用户 token」的伪需求
- 本项目无 WebSocket/实时推送，不存在 `$connect` 授权器这层问题；若日后加实时功能，该链路的 token 校验仍在 `$connect` 函数里，不迁移到 JWT 授权器

**约束：不要创建 `$default` 路由（G6）**

- `$default` 路由会捕获所有未显式定义的方法与路径，**包括 OPTIONS**；一旦存在，预检会被授权器拦成 401，刚补的 CORS 等于失效
- 硬约束：**不创建 `$default` 路由**。若确实需要兜底，必须显式声明 `OPTIONS /{proxy+}` 且 `authorization_type = NONE`（优先级高于 `$default`）
- 12.4 冒烟补一条：带 `Origin` 的 `OPTIONS /notes` 预检断言 200 且含 ACAO

**API 侧 CORS（补 v1.9 缺口）**

浏览器从 CDN 域名调 `execute-api` 域名属跨域，此前只配了 S3 桶 CORS。HTTP API 侧配置：`AllowOrigins` 为 **CDN 域名（从 `/cloudjian/cdn-domain` 注入，不写死）**，`AllowMethods` 为 `GET/POST/PUT/PATCH/DELETE/OPTIONS`，`AllowHeaders` 为 `authorization/content-type/if-match`，`ExposeHeaders` 为 `etag`，`MaxAge` 600 秒。**预检由网关直接应答（不带 Token 也不 401）**；Lambda **不需要也不应该**输出 CORS 头 —— 官方机制是**网关忽略集成返回的 CORS 头**（不是「去重」）。注意这意味着：日后若关掉网关 CORS 配置，后端补头也不会生效。

**ETag 的传递位置（G16）**：前端保存时把 ETag 放在请求头 `If-Match`（不是 body 字段），Lambda 取出后原样作为 S3 `PutObject` 的 `If-Match`；因此 `AllowHeaders` 必须包含 `if-match`。响应回传新 ETag 用 `ETag` 头，故 `ExposeHeaders` 为 `etag`。

**已知风险：网关 401 可能不带 CORS 头（G2）**

- 授权器拒绝发生在「集成之前」，请求根本没到 Lambda；而 HTTP API **没有 gateway responses 机制**（那是 REST 的能力），无法给 4xx 补 `Access-Control-Allow-Origin`
- 3.1 链路里业务 API **不经过 CloudFront**，也没有边缘函数能补头 → 浏览器可能把 401 表现为 CORS error，前端拦截器读不到 `status`
- 应对（三层，缺一不可）：
  1. 冒烟/验收带 `Origin: <CDN 域名>`，**硬断言 `status=401`**；ACAO **仅记录、不作为阻断项** —— 按官方机制「授权器在集成前拒绝、CORS 头只加在集成响应上」，401 无 ACAO 是**预期结果**（V1）。因此不得把「401+ACAO」写成 CI 断言，否则流水线会稳定失败。实测记录无 ACAO 时，必须确认前端第 2、3 层兜底（本地 `exp` 预判 + CORS error 分支）已生效
  2. 前端拦截器**先本地解 AccessToken 的 `exp`**，过期直接跳登录页，不等服务端 401（这是 20 小时到期的正常路径）
  3. `fetch` 抛出的网络/CORS 错误作为 Token 失效的兜底分支：连续失败且本地 `exp` 已过 → 清 Token 跳登录

**成本**：授权器本身不收费，被拒请求不产生 Lambda 费用，但**被拒请求仍按 HTTP API 请求计费**，且 Lambda 本来就在永久免费额度内 —— 因此**账单节省为 $0，不是 $0.01–0.05**。买到的是「伪造/垃圾 Token 不进 Lambda、不占并发、不产生冷启动、不打爆 CloudWatch 噪声」这道防线，以及迁移 HTTP API 时的零边际成本。**明确不计入省钱清单。**

### 12.2 依赖顺序与契约总线

首次搭建必须按序执行一次（单环境，无 `<env>` 区分），之后各自独立迭代：

```
infra（首次 apply：桶、Cognito、API GW 路由、IAM、SSM）
   ├─▶ backend（创建函数 + 发布 Layer 与代码 + 授权 API GW 调用）
   └─▶ frontend（拿到 API URL 与 Cognito 参数后才能正确构建）
```

三个仓库之间不共享代码，靠 **SSM Parameter Store** 做参数总线（标准参数免费）。**参数前缀统一为 `/cloudjian/<key>`（v1.11 单环境，不再有 `<env>` 段）**，三条流水线读同一套参数：

| 参数 | 写入方 | 读取方 | 用途 |
|---|---|---|---|
| `/cloudjian/bucket` | infra | backend、frontend | 代码包上传与静态资源同步的目标桶 |
| `/cloudjian/cdn-domain` | infra | frontend、infra | 构建时注入、缓存失效目标；**CORS `AllowOrigins` 与 11.1 的 `AWS:SourceArn` 都从这里派生** |
| `/cloudjian/cdn-arn` | infra | infra | OAC 桶策略 `Condition` 里的分发 ARN（禁止写死） |
| `/cloudjian/api-url` | infra | frontend | API 基址注入到构建产物 |
| `/cloudjian/user-pool-id` | infra | frontend、backend | 登录与验签 |
| `/cloudjian/client-id` | infra | frontend | App Client |
| `/cloudjian/region` | infra | 全部 | 区域常量 |
| `/cloudjian/lambda-exec-role-arn` | infra | backend | 创建函数时挂载的统一执行角色 |
| `/cloudjian/lambda-alias` | infra | backend | 发布时切换的别名（固定 `live`） |
| `/cloudjian/api-id` | infra | backend | 为集成授权定位 API 与资源 |
| `/cloudjian/jwt-authorizer-id` | infra | **infra CI（`get-routes` 门禁）** | 逐路由断言 `AuthorizerId` 的**期望值来源**，不是「诊断用」；后端运行时不依赖它（V7/G15） |
| `/cloudjian/release/*` | backend → `release/backend`；frontend → `release/frontend`；**infra 是 `release/archive` 的唯一写入方**（Y3） | 人工排障、`main` 归档 | 每条 key 只有一个写入方；三仓各自的 `release.yml` 只写自己那条，`archive` 由 infra 的 `release.yml` 写（tag + commit） |

规则：

- infra 每次 `apply` 后写入/更新这些参数；前后端 CI **每次构建都实时读取，不缓存、不落库**
- 前后端 CI 启动第一步先校验所需参数存在，缺失直接失败并提示「请先执行 infra 流水线」
- 参数变更（如换域名）后，前后端需各跑一次发布才能生效，infra 的 README 里列出触发清单

### 12.3 Lambda 全归后端：如何不产生循环依赖

决策：**Lambda 的一切（函数创建、代码、Layer、别名、超时内存、环境变量、API Gateway 集成授权）都由 `cloudjian-backend` 负责，`cloudjian-infra` 不创建也不更新任何 Lambda 资源。** 唯一例外是 **执行角色**：IAM 归 infra，infra 创建一个共享角色 `cloudjian-lambda-role`，后端创建函数时挂载它。

难点是 API Gateway 的集成需要函数 ARN，而 infra 不能等后端先建函数，否则首次部署死循环。解决方式是**用固定命名把 ARN 变成可推导字符串**：

```
arn:aws:lambda:ap-northeast-1:{account}:function:cloudjian-notes-api:live
```

- 函数名与别名由第 13 章命名规范固定，infra 直接在 Terraform 里拼出 ARN 字符串
- 集成资源只存这个字符串，**不校验函数是否存在**，因此 infra 可以先建集成
- 后端首次发布时按同样的名字建函数、建别名 `live`、再加调用授权，链路立刻打通
- 首次部署存在一个「路由已发布但函数未就绪」的窗口（接口返回 500/403），由 12.4 的部署顺序与冒烟检查兜住

对应契约（后端必须严格按此落地，任一不符则 API 调用失败）：

| 契约项 | 固定值 |
|---|---|
| 函数名 | `cloudjian-notes-api`、`cloudjian-share-api`、`cloudjian-asset-api`、`cloudjian-admin-api`、`cloudjian-export-api`、`cloudjian-maintenance-api`（定时任务入口：收件箱对账、契约校验、索引重建） |
| 别名 | `live`（API Gateway 集成指向别名 ARN，不指 `$LATEST`） |
| 执行角色 | `cloudjian-lambda-role` 的 ARN，从 SSM `/cloudjian/lambda-exec-role-arn` 读取 |
| 运行时 | `python3.14`（2029-06-30 弃用；**Layer 必须用同版本镜像构建**，见下） |
| 内存 / 超时 | 512 MB / **25 秒**（HTTP API 集成超时上限 30 秒，留 5 秒给网关；批处理预算按 15 秒设计，见 6.1） |
| 环境变量 | `CJ_BUCKET`、`CJ_REGION`、`CJ_USER_POOL_ID`、`CJ_LAYER_MODE=parquet`，从 SSM 读取后写入 |
| 运行时基线 | 后端 `python3.14`（Amazon Linux 2023）；前端构建 Node.js 24 LTS；CI 中 `actions/setup-node` 固定 `node-version: 24`，仓库放 `.nvmrc` 写 `24`、`package.json` 写 `"engines": {"node": ">=24 <25"}` |
| 调用授权 | 后端执行 `add-permission`，`SourceArn` 指向该 HTTP API 的 execute-api ARN（到 `api-id` 即可，如 `arn:aws:execute-api:ap-northeast-1:<acct>:<api-id>/*`；细化到 `api-id/*/GET/notes` 属可选） |

`cloudjian-lambda-role` 的权限（infra 定义，后端不可修改）：

- `s3:GetObject/PutObject/DeleteObject/ListBucket`（限数据桶 `users/*`、`users/*/exports/*`；**不含 `deploy/*`**——那是发布角色上传代码包的路径，运行时无用途，Y9 最小权限）
- `logs:CreateLogGroup/CreateLogStream/PutLogEvents`（限日志组 `cloudjian-*`；补 `CreateLogGroup` 保证日志组存在，属 `AWSLambdaBasicExecutionRole` 标准项）
- `cognito-idp:GetUser/AdminGetUser/AdminUserGlobalSignOut/AdminCreateUser/AdminAddUserToGroup/AdminRemoveUserFromGroup/AdminDisableUser/AdminEnableUser/AdminResetPassword`（限本用户池 ARN，动作逐一列出，不用 `cognito-idp:*`）
  - 这 6 个管理动作是 4.5 开通用户、2.1 禁用/启用/调角色、4.7 管理员重置密码的必需权限；v1.6 只列了 3 个读/签出动作，会让管理后台四项核心功能全部 AccessDenied（P0-2）
- 不使用 `s3:*`、不授予 `iam:*`

可追溯性：

- 后端每次发布把「函数名 / 代码版本 / 别名指向 / Layer ARN / commit」写 SSM（`/cloudjian/release/backend`）
- 后端**每周**跑一次「契约校验」作业：`list-versions-by-function` 与 `get-alias` 比对期望值，不符则告警——**固定跑在 Lambda Scheduler（`cloudjian-weekly-contract`），不占 GitHub Actions 分钟数**；12.8 的 CI 分钟只算漂移检查（Y9，消除三处载体不一致）
- infra 的漂移检查只覆盖自己管的资源，不再包含 Lambda，避免假阳性

**定时任务的归属**（P1-6）：

- 函数名固定为 `cloudjian-maintenance-api`，与其余 5 个同规则推导 ARN，**infra 只建 EventBridge Scheduler 规则**（目标指向 `...:function:cloudjian-maintenance-api:live`），不建函数
- 三类调度：`cloudjian-daily-reconcile`（每日，收件箱对账）、`cloudjian-weekly-contract`（每周，契约校验）、`cloudjian-daily-index-check`（每日，索引完整性抽查，只读）
- 前端触发不了这些任务，全部由 Scheduler 调用，后端函数只负责实现
- **调度执行角色 `cloudjian-scheduler-role`**（F4）：信任主体 `scheduler.amazonaws.com`，并在信任策略里用 `aws:SourceAccount` + `aws:SourceArn`（限 `cloudjian-*` 调度组）收窄，防止被其他账号的调度服务冒用；权限只有 `lambda:InvokeFunction`，资源锁定 `...:function:cloudjian-maintenance-api:live`（别名 ARN）

### 12.4 三条流水线（单环境：dev 即线上）

**发布模型（v1.11 简化，原 17.7 的三环境方案取消）**：只保留**一个部署环境 `dev`**，合入 `dev` 即发布上线；`main` 只归档、不部署。PR 即审批，不再有 staging/prod 两级与 Environment reviewer。

```
feat/xxx ──PR──► dev（合并即部署上线）──PR──► main（归档，不部署）
                    │                              │
                    └ GitHub Environment: dev       └ 只打 tag + 写发布记录
```

| 触发分支 | 是否部署 | 部署目标 | 审批 | 说明 |
|---|---|---|---|---|
| `feat/*` | 否 | — | — | 只跑 lint / 类型检查 / 单测，并在 PR 上贴 Terraform plan 摘要 |
| `dev`（由 feat PR 合入） | **是** | 唯一环境（资源无环境后缀） | PR + CI 全绿（0 批准，单人；≥2 人时 1 人 review） | 合并即上线；回滚 = revert 该 PR；未关联 PR 的 commit 不部署 |
| `main`（由 dev PR 合入） | 否 | — | PR 评审 | 只打 tag、写 `/cloudjian/release/archive`，**不含任何部署步骤** |

**事件与归档 workflow（X15 保留）**：部署 workflow 触发 `push` 到 `dev` **以及 `pull_request`**（后者只跑校验、在 PR 上贴 Terraform plan 摘要，不部署）；`main` 上单独一条 `release.yml`，触发 `push` + `tags`，动作只有「打 tag、生成 CHANGELOG 片段、写 `/cloudjian/release/archive`」，**不含任何部署步骤**。

**`environment` 声明是硬约束（Y1）**：**凡需要 AWS 凭证的 job 必须声明 `environment: dev`**——包括三仓的部署 job，以及 infra 在 `pull_request` 事件里跑 plan 的 job。原因：`sub` 只在声明 environment 时才是 `repo:org/<repo>:environment:dev`；push 未声明会变成 `ref:refs/heads/dev`、pull_request 未声明会变成 `pull_request`，两者都不匹配信任策略，`AssumeRoleWithWebIdentity` 直接失败（与 X1 同型）。纯 lint/单测 job 不需要声明。不要给部署角色开放 `pull_request` 信任条件；若要让 PR 的 plan 有凭证，复用一个只读的 plan 角色。

三仓 workflow 只在 `dev` 上部署，`feat/*` 与 `main` 不部署。**`dev` 分支就是生产**——没有「先预发再上线」的缓冲，因此进入 `dev` 前的 PR 评审与 CI 必须跑满（12.4 各工程的冒烟步骤就是上线门禁，不能裁剪）。

**仓库可见性：三仓全部 public（v1.12 定稿，Y2）**。这样在 GitHub Free 下就**可用原生分支保护与 rulesets**（私有仓才需要 Pro），同时 Actions 标准 runner 免费且不消耗额度。代价是桶名、账户 ID、角色 ARN、桶策略与 CI 配置全部公开——按下面四条约束处理，而不是靠「没人知道」。

**分支与合并门禁**：

1. **原生分支保护**（public + Free 可用）：`dev` 与 `main` 都要求「必须通过 PR 合并」+「CI 状态检查通过」，并勾选 **Include administrators**（默认不约束 admin，不勾等于留后门）。
2. **部署侧二次校验**（纵深防御，保留）：部署 job 前置跑 `gh pr list --search <sha> --state merged`，查不到即失败、不部署——防的是「有人用 admin 旁路直推」。
3. 直推 `dev` 被分支保护拒绝；即便用 admin 旁路，部署门禁也会拦住不上线。本地 `pre-push` hook 只作提示。
4. **公开仓的配套约束**：①`pull_request_target` **禁止**用于任何需要 AWS 凭证的 job（fork PR 能改工作流代码，等于递凭证）；②外部协作者的 PR 一律需维护者批准后才跑 workflow；③GitHub Actions 全部按 commit SHA 锁版本；④开启 secret scanning + push protection（公开仓免费）。
5. **单人开发下「1 人 review」不成立**（GitHub 不允许作者批准自己的 PR）：`dev` 只要求「PR + CI 全绿 + 0 批准」。若有第二人加入，把 required approvals 调到 1，无需升级计划。
6. **信息公开后的补强**：账户 ID 一律用 `data.aws_caller_identity` 推导，不在 Terraform 里写死；桶名的可用性不靠保密，而靠 11.1 的 Block Public Access + OAC + 白名单；CI 每次 apply 后跑匿名穿透断言（`users/*` 必须 403），把「策略配错立刻被发现」变成自动检查而非靠人盯。

**为什么取消三环境**：三套资源让 CI 分钟数、IAM 复杂度、跨环境残余面同时上升（v1.10.1 已为此写了一整节残余面），而 100 人内部工具没有「预发验收」的真实需求，收益抵不上维护成本。代价是**没有独立预发环境**：破坏性变更（如生命周期规则、桶策略）只能在 dev 上先小范围造数验证再合并，或临时开一套本地/临时栈演练。

**前端工程 `cloudjian-frontend`**（触发：`dev` 分支 push + 相关 `pull_request`；`feat/*` 与 `main` 不部署，`main` 只跑归档 workflow）

| 步骤 | 内容 |
|---|---|
| 1 | 读 SSM 参数，注入 `VITE_API_URL`、`VITE_USER_POOL_ID`、`VITE_CLIENT_ID`、`VITE_REGION` |
| 2 | `actions/setup-node`（`node-version: 24`，带 npm 缓存）→ `npm ci` → 类型检查 → 单测 → `npm run build` |
| 3 | `aws s3 sync dist/ s3://{bucket}/web/ --delete`，静态资源带内容哈希，`index.html` 设 `no-cache` |
| 4 | `aws cloudfront create-invalidation --paths "/web/*"`（`index.html` 位于 `/web/index.html`，已被该通配覆盖，不再单列；Y9） |
| 5 | 冒烟（网关鉴权）：无 `Authorization`、篡改签名、过期 Token 三种请求调用 `/notes`，断言 401；**HTTP API 的 401 响应体为 `{"message":"Unauthorized"}`、常见响应头为 `WWW-Authenticate`，不是 REST 时代的 `x-amzn-errortype`**（G10）。三种用例都要带 `Origin: <CDN 域名>`，**断言 `status=401`**；ACAO **只记录、不作阻断项**（V1/W4）。再用**合法 ID Token** 断言 401（证明中间件 `token_use` 生效）、合法 AccessToken 断言 200。两种合法 Token 由 CI 用测试账号现取：infra 预置 `cloudjian-ci-test-user`（固定密码轮换、存 Secrets），流水线以 `USER_SRP_AUTH` 登录拿 Token，用完即 `GlobalSignOut`（V8） |
| 5c | 冒烟（预检与路由挂载）：`OPTIONS /notes` 带 `Origin` 断言 200 且含 ACAO；`apigatewayv2 get-routes` 断言 8 组业务路由 `AuthorizationType=JWT` 且 `AuthorizerId` 与 SSM 一致，且**不存在 `$default` 路由**（G4/G6） |
| 5b | 冒烟（Function 行为矩阵，F2）：`/`、`/login`、`/notes`、`/admin`、`/notes/abc` 均 200 且返回同一份 index；`/users/xxx/notes/a.md`、`/users/xxx/index.parquet`、`/users/xxx/.dir_meta.json`、`/users/xxx/assets/private/x.png` 均 403；`/users/xxx/assets/public/x.png` 200；`/web/missing.js` 为 404（不得被改写成 HTML） |

**后端工程 `cloudjian-backend`**（触发：同前，仅 `dev` 分支部署）

| 步骤 | 内容 |
|---|---|
| 1 | 读 SSM 参数 |
| 2 | 用 `public.ecr.aws/lambda/python:3.14` 镜像构建 fastparquet/numpy 依赖，产出 Layer zip（**L1 硬校验：`python -c "import sys; assert sys.version_info[:2]==(3,14)"` 后在镜像内 import 一次依赖，版本或 ABI 不符即失败**）；以 lockfile+运行时版本的组合哈希为键缓存在 `deploy/layers/{hash}.zip`，命中即跳过构建（直接控制 CI 分钟数），未命中才编译 |
| 3 | 业务代码打包为函数 zip（不含依赖） |
| 4 | 上传 zip 到 `deploy/backend/{sha}.zip` |
| 5 | 发布 Layer 版本（如变更）→ **创建或更新 6 个函数**（含 `cloudjian-maintenance-api`；名称、运行时、内存超时、环境变量按 12.3 契约）→ 更新代码 → `publish-version` → 切别名 `live` |
| 6 | 补 `add-permission`，授权 HTTP API（API ID 从 SSM `api-id` 读取）调用 **5 个 HTTP 接口函数**；`cloudjian-maintenance-api` **不挂 API Gateway、不需要 `add-permission`**，其对内调用由 `cloudjian-scheduler-role` 的 IAM 策略承担（F4）。按 12.2 依赖顺序，执行到这一步时 infra 必已完成，**不设「不存在则跳过」分支** |
| 7 | 冒烟：直接 `invoke` 别名跑健康检查路径，断言 200；**另做一次读写烟测——临时 key 固定为 `deploy/smoke/{sha}.txt`（由 CI 的部署角色写删，不放 `users/` 下、不打 `cj:retention`），写后立即删除并断言删除成功（`head-object` 返回 404），失败重试前先清理同前缀残留**；调用 `release` 元数据写回 SSM（**依赖 12.5 backend 角色的 `s3:DeleteObject`**，v1.13.3 K1；缺该权限则删除稳红） |
| 8 | 失败：别名回指上一版本，输出回滚结果，流水线标红 |

**基础设施工程 `cloudjian-infra`**（触发：同前；`terraform.workspace` = `tokyo`）

| 步骤 | 内容 |
|---|---|
| 1 | `terraform fmt -check` → `validate` → `tflint` → `checkov`（安全规则） |
| 2 | `terraform plan -out`，输出变更摘要到 PR 评论 |
| 3 | 合入 PR 即视为审批（单人：PR + CI 全绿、0 批准）；apply 走 GitHub Environment `dev`（无需额外 reviewer，审批在 PR 环节完成） |
| 4 | `terraform apply`，随后把输出写入 SSM 参数 |
| 5 | **每周**定时 `plan` 漂移检查（每日跑会烧 Actions 分钟数），有差异则开 Issue |
| 6 | 变更涉及桶策略/分发行为时，自动触发匿名穿透测试 |

### 12.5 OIDC 角色：三仓各一条

全部通过 GitHub OIDC 联邦，无长期 AK/SK。**每个仓库一条角色，共 3 条，互不复用**（v1.11 随单环境简化，原「3 仓 × 3 环境 = 9 条」取消）。

| 角色 | 绑定 `sub`（Environment 口径） |
|---|---|
| `cloudjian-gha-frontend-role` | `repo:org/cloudjian-frontend:environment:dev` |
| `cloudjian-gha-backend-role` | `repo:org/cloudjian-backend:environment:dev` |
| `cloudjian-gha-terraform-role` | `repo:org/cloudjian-infra:environment:dev` |

> **`sub` 必须用 `environment:` 口径（X1 的结论保留）**：GitHub 官方规定，job 声明 `environment:` 后，OIDC token 的 `sub` 为 `repo:ORG/REPO:environment:ENV`，**不是** `ref:refs/heads:<branch>`。若按分支口径写，三条角色全部 assume-role 失败、部署 100% 拿不到凭证。条件键用 `StringEquals` 精确匹配，不要 `StringLike`。
>
> **版本提醒**：GitHub 于 2026-07-15 后新建仓库可能启用 immutable subject claims（`sub` 形如 `repo:org@id/repo@id:environment:dev`），首次配置必须用 `aws sts assume-role-with-web-identity` 回读一次实际 `sub` 再定稿信任策略（15.14 实测项⑧）。

| 角色 | 绑定仓库 | 允许动作 |
|---|---|---|
| `cloudjian-gha-frontend-role` | `cloudjian-frontend` | `s3:PutObject/DeleteObject/ListBucket`（限 `web/*`）、`cloudfront:CreateInvalidation`、`ssm:GetParameter`（限 `/cloudjian/*`）、`ssm:PutParameter`（**仅限 `/cloudjian/release/frontend`**，Y3） |
| `cloudjian-gha-backend-role` | `cloudjian-backend` | `s3:PutObject/GetObject/DeleteObject`（限 `deploy/*`；**DeleteObject 为 H4 冒烟的「写后即删」与重试清残留所必需**，v1.13.3 K1）、`lambda:CreateFunction/DeleteFunction/GetFunction/GetAlias/ListVersionsByFunction/UpdateFunctionCode/UpdateFunctionConfiguration/PublishVersion/UpdateAlias/AddPermission/PublishLayerVersion/InvokeFunction/GetPolicy`、`iam:PassRole`（**精确到 `cloudjian-lambda-role` 的 ARN**）、`ssm:GetParameter`（限 `/cloudjian/*`）、`ssm:PutParameter`（**仅限 `/cloudjian/release/*` 与 `/cloudjian/lambda-*`**，不得覆盖 `api-url`、`bucket` 等 infra 参数） |
| `cloudjian-gha-terraform-role` | `cloudjian-infra` | `iam:*`（**显式列举 `cloudjian-*` 角色 ARN**）、`s3:*`（限数据桶与 state 桶，ARN 显式列举）、`cloudfront:*`、`cognito-idp:*`、`apigateway:*`、`logs:*`（限 `/aws/lambda/cloudjian-*` 日志组）、`ssm:PutParameter`（限 `/cloudjian/*`）、`budgets:*`（限名称 `cloudjian` 的预算）、`scheduler:CreateSchedule/GetSchedule/UpdateSchedule/DeleteSchedule/ListSchedules/CreateScheduleGroup/DeleteScheduleGroup`（限 `cloudjian-*` 调度组）、`iam:PassRole`（仅限 `cloudjian-scheduler-role`）、`iam:GetRole`。**不含 `lambda:*`**，从权限层面保证 infra 无法碰函数（F4：漏了 scheduler 动作会让 apply 建调度时 AccessDenied，并可能留下半应用状态） |

**公开仓对信任策略的影响（v1.12）**：三仓公开后，任何人都能看到三条角色的 ARN 与 `sub` 规则，但**不构成冒用条件**——信任策略是 `StringEquals` 精确到 `repo:org/<repo>:environment:dev`，别人 fork 出来的仓库 `sub` 是自己的仓库名，`AssumeRoleWithWebIdentity` 会被拒。**不要把 `sub` 放宽成 `StringLike` 或只写 org 前缀**，否则公开仓会把这个「不可冒用」前提打破。

**关于跨环境越权（X2 已随简化消解）**：现在只有一个环境，原「dev 凭证可操作 prod 资源」的残余面**不再存在**——发布角色被允许操作的就是线上资源本身。但这意味着 **who can merge to `dev` = who can change production**。控制手段按 Y2 的最终方案（v1.12 三仓 public）：**原生分支保护**（必须经 PR + CI 全绿 + Include administrators）是平台强制，部署侧再校验「commit 必须关联已合并 PR」作纵深防御；`main` 只接收来自 `dev` 的 PR。若日后要恢复多环境，X2 的收窄清单（独立 state 桶、显式角色 ARN、日志组与预算按环境限定）仍适用于当时的重建。

> 复审 N2 的 4 项缺口已补齐：`iam:PassRole`、`s3:GetObject`（`deploy/*`）、SSM 读取范围放宽到 `/cloudjian/*`、`lambda:GetAlias` 与 `ListVersionsByFunction`（契约校验用）；执行角色另补 `logs:CreateLogGroup`。

### 12.6 网络与 VPC（决策：不建 VPC）

结论：**云笺不建 VPC。Lambda 直接运行在默认网络，通过公网访问 S3、Cognito、API Gateway。**

#### 12.6.1 决策依据

| 判断项 | 结论 |
|---|---|
| 是否有必须进 VPC 的资源 | 没有。无自建数据库、无缓存、无中间件，全部依赖都是公网可访问的 AWS 托管服务 |
| Lambda 在 VPC 内如何出网 | 只有 NAT 一条路。Cognito 没有任何 VPC Endpoint，S3/Logs 的 Endpoint 替代不了它 |
| 三种方案的代价 | NAT Gateway：+$45/月；NAT 实例：+$4/月，但多一台 EC2 成为单点，登录全链依赖它；IPv6 双栈：+$0，但 Lambda 双栈出网与 Cognito 双栈端点需先做技术验证，未验证即上线属于赌博 |
| 安全收益 | 对 100 人内部工具，VPC 的隔离价值有限（Lambda 无入站端口，出网仍要经 NAT 出公网），抵不过新增的运维面与单点风险 |

真正的安全边界由这三项构成，与 VPC 无关：执行角色的最小权限、桶策略精确到 `web/*` 与 `users/*/assets/public/*`、前端永不直连 S3。

| 已知取舍（G14） | 说明 |
|---|---|
| 发布角色权限 = 线上权限（v1.11 单环境后） | 取消多环境后，「dev 凭证可操作 prod 资源」的跨环境问题不存在；新的等价风险是**谁能合入 `dev` 谁就能改线上**。控制手段：**原生分支保护**（public 仓 + Free 可用，Include administrators）+ 部署侧校验（未关联已合并 PR 的 commit 不部署）+ 三条角色按最小权限列举（SSM 前缀、桶 ARN、`iam:PassRole` 目标、日志组、预算名）。不再保留「每环境独立 AWS 账号」的演进项——只有单环境，无跨环境可隔离 |
| `cloudjian-gha-terraform-role` 的区域通配 | `apigateway:*` 可收窄到 `arn:aws:apigateway:ap-northeast-1::/apis/*` 做区域限定。单环境后不再有「区域限定≠环境限定」问题；剩余取舍是 API ARN 含随机 `api-id`，无法按名字收窄 |

#### 12.6.2 保留的取舍

- Lambda 出网走公网，没有安全组/网络 ACL 级隔离；补偿手段是 IAM 最小权限 + 桶策略前缀化 + 关停 S3 公共访问
- infra 仓库保留 `network.tf` 空模块与 `enable_vpc = false` 变量，写清接线说明（VPC、两公有/两私有子网、NAT 实例、S3 Gateway Endpoint、函数挂载点），但**不部署任何网络资源**
- 若日后出现合规要求，演进路径就绪：打开 `enable_vpc`、补 NAT 实例、backend 发布时给函数加 `vpc_config`，业务代码无需改动，成本 +$4/月

#### 12.6.3 未来若必须上 VPC 的前置条件

真到那天，先满足这三条再动手：确认合规条款是否接受「Lambda 落私有子网」；接受 NAT 实例单点并配置健康检查自动重启；在预发环境跑通「Cognito JWKS 可达 + S3 Gateway Endpoint 可达 + CloudWatch 可写」三项验收。

### 12.7 可观测性与备份

- CloudWatch Logs 保留期 **30 天**，日志组名 `cloudjian-<函数>-api`；**审计类事件（共享授权/撤销等）同为该组内的结构化 JSON 行**，不另建存储（v1.13.3，K4）
- 告警：Lambda 错误率、API 5xx、CloudFront 5xx、412 冲突率异常、后端发布失败、Budgets 超阈值
- AWS Budgets 阈值 $5/月（**仅覆盖 AWS 侧**），80% 邮件提醒，100% 再提醒；GitHub Actions 在三仓公开后免费（标准 runner 不消耗额度），无需单独预算；若日后改回 private，再设 spending limit $10
- 激活 Cost Allocation Tags（`Project/Component/Environment/ManagedBy`），否则账单无法按项目归集
- S3 Versioning 开启，并**必须配套非当前版本生命周期**，否则旧版本永续累积
- **生命周期一律用标签过滤，不用通配符前缀**（P0-1 整改）：S3 生命周期规则的 `prefix` 是纯字面前缀匹配、不支持 `*`；`users/*/trash/`、`users/*/versions/`、`users/*/exports/` 这类写法 Terraform 与 S3 都会接受，但命中 0 个对象且不报错。写入侧由 Lambda 在 `PutObject` 时打标签：

| 对象 | 写入侧标签 | 规则 |
|---|---|---|
| `trash/` 下任何对象（**含 Copy 移入**） | `cj:retention=30d`（Copy 用 `TaggingDirective=REPLACE`） | 当前版本 30 天过期 |
| `versions/` 下任何对象 | `cj:retention=30d` | 当前版本 30 天过期 |
| `assets/_trash/` 下任何对象（**含随笔记删除移入的图片**） | `cj:retention=30d`（Copy 用 `TaggingDirective=REPLACE`） | 当前版本 30 天过期（Y9：8.3 已写、原表漏列） |
| `exports/` 下任何对象 | `cj:retention=1d` | 当前版本 1 天过期 |
| 全桶（兜住高频覆写文件） | 无标签要求 | `NoncurrentVersionExpiration: NoncurrentDays=7` + `newer_noncurrent_versions=3`；`AbortIncompleteMultipartUpload: DaysAfterInitiation=7` |

- 三条规则落地为一个 `aws_s3_bucket_lifecycle_configuration`：`filter { tag { key="cj:retention" value="30d" } }`、`filter { tag ... "1d" }`、`filter {}`（桶级非当前版本清理）
- **笔记正文（`notes/` 下）不再单独放宽 30 天**（P2-3）：md 的历史由 `versions/` 承担，给它配非当前版本 30 天属于方向反了，而且只能用通配前缀实现、根本配不出来
- 写入/拷贝侧统一由 `put_with_retention()` / `copy_with_retention()` 打标签，CI 用 grep 门禁拦裸 `put_object`、`copy_object`、`upload_file`（17.8–17.10）；标签值只有 `30d`/`1d` 两种，新增档位必须同步新增规则
- **验收标准**：造 4 类测试对象（**经 Copy 路径进 trash 的**、versions、exports、普通笔记），逐个 `get-object-tagging` 确认标签存在、`list-objects-v2` 确认命中数 > 0；8 天后确认高频覆写文件的非当前版本 ≤ 3 份；31 天后 trash/versions 清空。**「terraform apply 成功」不能作为生命周期验收依据**
- 依据：S3 `Expiration` 只作用于当前版本，对非当前版本无效；被高频覆写的 `index.parquet`、`search/shard-*.json.gz`、`_refs.json`、`jobs/*.json`、`_share_inbox.parquet`、`_registry.parquet` 若不配非当前版本清理，旧版本会永久增长（N4：A 档约 +2.9 GB/月，C 档约 +17 GB/月）
- 空 filter 那条规则同时设 `expired_object_delete_marker=true`，否则删除标记会永久堆积（删到只剩一个 delete marker 时，它既不是当前版本也不受保留数约束）（F12）
- 状态桶开启版本控制，每月一次 `aws s3 sync` 全量备份到本地或另一区域
- 三仓各自的部署记录（commit → 发布版本 → 别名指向）写入 SSM 或制品仓库，便于追溯

### 12.8 成本模型（三档，东京区，免费期后）

用量假设：

| 参数 | 基准 A | 活跃 B | 高负载 C |
|---|---:|---:|---:|
| 用户数 | 100 | 100 | 100 |
| 人均笔记数 | 1,000 | 2,000 | 5,000 |
| 笔记平均大小 | 3 KB | 3 KB | 3 KB |
| 人均图片（300 KB） | 200 | 300 | 500 |
| 总存储 · **当期对象**（非当前版本另计） | ≈ 6.5 GB | ≈ 10 GB | ≈ 17.5 GB |
| 人均每天编辑次数 | 5 | 15 | 30 |
| 人均每天 API 请求 | 30 | 60 | 120 |
| 搜索触发 | 1 次/人·天 | 2 次/人·天 | 2 次/人·天 |

核算口径（G7）：用量假设按**每月 22 个工作日**折算（100 人 × 5/15/30 次/天 × 22 = 11k / 33k / 66k 次编辑），API 请求同理（100 × 30/60/120 × 22 = 66k / 132k / **264k**；此前写的 300k 相当于 25 个工作日，与 22 天口径不符 —— V5）；换算成 30 天口径会让请求费项整体约 $0.2–0.9 上浮，结论不变，但**同一份文档只用一种口径**。

核算（按复审口径拆分，免费期后，USD/月）：

| 成本项 | A | B | C | 口径说明 |
|---|---:|---:|---:|---|
| S3 存储 · 当期对象 | $0.16 | $0.25 | $0.44 | 6.5 / 10 / 17.5 GB × $0.025 |
| S3 存储 · 非当前版本（保留 3 份） | $0.02 | $0.02 | $0.03 | ≈ **0.8 / 0.8 / 1.2 GB**（按金额 ÷ $0.025 反算，即高频覆写文件各留 3 个旧版；W3 修正了此前「≈0.1 GB」的错误标注）；若不配 `NoncurrentVersionExpiration` 会逐月增长（见 12.7） |
| S3 请求 · PUT | $0.28 | $0.83 | $1.65 | 每次保存按 **5 次 PUT 保守计**（正文 + 旧版本 + 索引 + 搜索分片 + `_refs.json`）；其中 `_refs.json` 按 8.3 是**条件写**（仅图片引用变化时），实际约 4 次，按 4 次可再省 ≈$0.06 / $0.17 / $0.33 —— 已在 8.3 对齐，未并入本表（G7） |
| S3 请求 · GET | $0.05 | $0.10 | $0.21 | 读正文、读索引/分片、注册表刷新、jobs 轮询、导出下载 |
| S3 请求 · LIST | $0.00 | $0.00 | $0.00 | 收件箱索引改造后无全库遍历（7.2） |
| Lambda | $0 | $0 | $0 | 远低于永久免费 100 万请求 / 40 万 GB·s |
| API Gateway HTTP API | $0.07 | $0.13 | $0.26 | 6.6 万 / 13.2 万 / **26.4 万**次 × $1.00/百万（v1.8 由 REST 切换；REST 基准按 26.4 万为 $0.23 / $0.46 / $0.92；**历史值 $0.23 / $0.46 / $1.05 中的 $1.05 是 30 万口径，不可与现值混用** —— V5/X13） |
| CloudFront | $0 | $0 | $0 | 低于永久免费 1 TB 出站 + 1,000 万请求；**失效路径按批合并**（X9）：删图/删笔记按用户批处理，用 1 条通配失效（`/users/{uuid}/assets/public/*`）覆盖多文件，月度失效条数控制在 1,000 条免费额度内，超出按 $0.005/路径（C 档若逐文件失效会到 $4.9–28/月，故此项必须批量化） |
| Cognito | $0 | $0 | $0 | 100 MAU < 10,000 MAU 免费额度 |
| CloudWatch Logs | $0（见口径） | $0（见口径） | $0（见口径） | **双口径，未坐实前不写成定论（W1）**：估算 ingest 约 0.4 / 0.8 / 1.58 GB/月（C 档 26.4 万请求 × 6KB）。①若 5GB/月免费额度**覆盖 vended logs** → $0（本表采用，合计 $0.61 / $1.38 / $2.67）；②官方计费页明确「标准费率适用于其他服务写入 CloudWatch Logs 的日志（例如 VPC 流日志与 Lambda 日志）」，且 Lambda 日志自 2025-05-01 起归类为 **Vended Logs** → 按东京 $0.76/GB 为 **$0.30 / $0.60 / $1.20**，合计上修至 **$0.91 / $1.98 / $3.87**（含审计增强项 3.2 / 6.4 / 14.9），仍 < $5。**首月实账后回填这一格**，详见 15.11 实测项 |
| GitHub Actions（公开仓） | $0 | $0 | $0 | **三仓 public（v1.12）**：标准 runner 免费且不消耗额度，**无 2,000 分钟上限**，无需 spending limit（保留 $10 兜底亦可）。**单环境后估算（v1.11）**：PR 校验（三仓 × 每周 8 次 × 6 分钟）≈ 576 分钟、dev 合入部署（30 次 × 12 分钟）≈ 360、**每周漂移检查 ≈ 60**（契约校验跑在 Lambda Scheduler，不占 CI 分钟，Y9；**该估算 v1.11.1 由 ≈100 收敛为 ≈60，故合计由 ≈1,040 变 ≈1,000，H5**），合计 **≈1,000 分钟/月**——公开仓标准 runner **不计费**，该数字只作运行负载参考 → **$0**，无额度上限、无需 spending limit |
| 杂项（日志对象、状态桶增量备份、制品） | $0.03 | $0.05 | $0.08 | 量级极小 |
| **合计（稳态）** | **≈ $0.55–0.67** | **≈ $1.24–1.52** | **≈ $2.40–2.94** | **中心值 = 明细逐项加总**（固定此定义，不用区间中点）：**$0.61 / $1.38 / $2.67**；区间为该值 ±10%（PUT/GET 波动），故端点与宽度严格跟随中心值（V2/V4/V5 修正后重算） |
| 若开 CloudTrail 数据事件 | +$2.3 | +$4.4 | +$11 | 默认关闭，排障时临时开 |
| **含审计增强项** | ≈ $2.9 | ≈ $5.8 | ≈ $13.7 | 中心值 + $2.3 / $4.4 / $11 |

**取值规则（X14，v1.11.1 定稿）**：所有明细**截断到分（向下取整，不四舍五入）**后逐项相加。因此 0.8 GB × $0.76 = $0.608 → **$0.60**；三档日志分别为 **$0.30 / $0.60 / $1.20**，上修合计按「各档中心值 + 各档日志」逐档相加：A 档 0.61+0.30=**$0.91**、B 档 1.38+0.60=**$1.98**、C 档 2.67+1.20=**$3.87**（**不是** 0.30+0.60+1.20 相加）；含审计 B 档为 **$6.38**，不再缩写为 $6.4。此前「四舍五入」与「$1.98」并存才导致 1.38+0.61=1.99 的矛盾；现统一为截断，表内数字不变。

关键结论：

- **只算一套环境（v1.11）**：`dev` 分支就是线上，本节三档即全部 AWS 支出，不再有 dev/staging 增量，也不再有「临时栈 destroy 后 SSM 参数残留」的问题。若为演练临时起一套栈，按小桶 + 分发 + 用户池估算 $0.03–0.08/月·套；**演练栈必须用独立命名与独立参数前缀**（`cloudjian-drill-*`、`/cloudjian-drill/*`，Y8），用完只销毁 drill 前缀与 drill 资源——沿用 `cloudjian-*` 会与线上互相覆盖，销毁时会误删线上参数
- 成本对活跃度线性敏感，不再对「全量搜索」异常敏感（v1.0 该项占 S3 请求费 80%，已改造）
- 口径说明（v1.6 审核 P3-4）：早期「含 30 天版本」的 14.4 / 25.8 / 55.8 GB 是**上限估计**，稳态实际是**当期 6.5 / 10 / 17.5 GB + 非当前 0.8 / 0.8 / 1.2 GB**（X6：原句漏掉非当前这一段，与假设表和明细行冲突）；同一份文档内两套口径曾互相矛盾，现已统一
- **不要**把小文件转 Standard-IA/Glacier：3 KB 笔记转 IA 后存储费反涨约 40 倍（128 KB 最小计费 + 30 天最短存储）
- 真正的大头是人力：三个工程的流水线维护、Layer 编译、索引排障，都是数百小时量级
- **区域单价校正（G5）**：上表 API Gateway 用的是 **$1.00/百万的美东目录价**（官方 $3.50 示例也只覆盖美东/俄勒冈/孟买）。ap-northeast-1 实际约为 **HTTP $1.29/百万、REST $4.25/百万**，S3 东京请求价略低于美东（PUT ≈$0.0047/千、GET ≈$0.00037/千）。按东京价重算：API Gateway 行变为 ≈$0.09 / $0.17 / **$0.34**（26.4 万 × $1.29/M），S3 请求费的下降大致抵消，**三档净影响 < $0.1/月**；而 REST→HTTP 在东京口径实省 ≈**$0.20 / $0.39 / $0.78**（26.4 万 × $2.96/M），比上表更划算。落地后请用首月实账（按 ap-northeast-1）校准一次
- **已执行**：API Gateway 由 REST 换 HTTP API，单项 $0.23 / $0.46 / **$0.92** → $0.07 / $0.13 / $0.26（均按 26.4 万请求；**API Gateway 单项**降幅 $0.16 / $0.33 / **$0.66**/月）。此前把该单项降幅写成「三档合计降幅」，是口径错误，已纠正（G3/V10）。**跨版本对比统一按「明细合计」**：v1.7.1 $0.84 / $1.84 / $3.76（含日志行与 C 档 30 万请求）→ v1.9.2 **$0.61 / $1.38 / $2.67**（日志归零 + C 档 26.4 万 + 网关降价三项叠加，降幅 $0.23 / $0.46 / $1.09）。导出走预签名、无 API Key / Usage Plan / 网关缓存 / WAF，切换无功能损失；REST 独有能力本期一个都没用到

### 12.9 暂停项与边界

- `analytics/` 自动导出工作流本期不做，Parquet 的离线分析用 DuckDB 现场查代替
- CloudTrail 数据事件默认关闭，仅在排障窗口临时开启
- `enable_vpc = false`：不部署任何网络资源，`network.tf` 仅保留空模块与接线说明

---

## 13. 资源命名规范

云笺的全部云资源统一以 `cloudjian` 作为标识前缀，保证在 AWS 控制台、日志、Terraform 输出中一眼可辨归属。

### 13.1 四条基本规则

1. **全小写 + 连字符**：AWS 资源名统一 `kebab-case`；代码内模块与变量用 `snake_case`
2. **前缀固定**：所有资源名以 `cloudjian-` 开头，后接用途，必要时再接区域
3. **区域后缀给「名称需全局或跨区可辨」的资源**：S3 桶名全球唯一、Cognito Hosted UI 域名全局唯一，必须带区域；Lambda、API Gateway、IAM 等账号内唯一的资源不带区域
   - 修正说明：`cloudjian-userpool-tokyo` 只是 User Pool 的**显示名称**（区域内可重名），带 `-tokyo` 是为可读性而非硬约束；真正必须带区域的是 Hosted UI 前缀域名。云笺自建登录页走 `InitiateAuth`，不使用 Hosted UI，故域名不纳入命名体系。
4. **名字只描述稳定属性**：资源名不写版本号、时间、人员名；版本与环境由变量与标签表达

配套标签（Terraform 统一注入）：

```
Project     = cloudjian
Component   = api | web | storage | auth | cdn
Environment = dev    # 单环境；Terraform var 注入，禁止写死
ManagedBy   = terraform
```

> 成本归集不靠资源名前缀，而靠上述标签 + 在 Billing 控制台**激活 Cost Allocation Tags**（见 12.7）。

### 13.2 资源命名对照表

| 资源类型 | 命名规则 | 云笺中的实际命名 |
|---|---|---|
| 数据桶 | `cloudjian-data-<region>` | `cloudjian-data-tokyo` |
| Terraform 状态桶 | `cloudjian-tfstate-<region>` | `cloudjian-tfstate-tokyo` |
| S3 顶层前缀 | 固定两类 | `web/`、`users/` |
| 用户子前缀 | 固定八类 | `notes/`、`trash/`、`versions/`、`assets/`、`shares/`、`search/`、`jobs/`、`exports/` |
| Lambda 函数 | `cloudjian-<模块>-api` | `cloudjian-notes-api`、`cloudjian-share-api`、`cloudjian-asset-api`、`cloudjian-admin-api`、`cloudjian-export-api`、`cloudjian-maintenance-api` |
| Lambda Layer | `cloudjian-<用途>-layer` | `cloudjian-parquet-layer` |
| Lambda 别名 | 固定 `live`，不带环境后缀 | 别名 `live`（12.3 的 ARN 推导依赖此固定值） |
| API Gateway（HTTP API） | `cloudjian-<用途>` | `cloudjian-api`，Stage `dev`（类型固定 HTTP API，不建 REST API） |
| Cognito 用户池 | `cloudjian-userpool-<region>` | `cloudjian-userpool-tokyo` |
| Cognito App Client | `cloudjian-web-client` | `cloudjian-web-client` |
| Cognito Group | `cloudjian-<角色>` | `cloudjian-admin`、`cloudjian-user` |
| CloudFront 分发 | `cloudjian-cdn`（Comment） | `cloudjian-cdn` |
| CloudFront Function | `cloudjian-path-whitelist` | `cloudjian-path-whitelist` |
| IAM 角色 | 运行角色 `cloudjian-<用途>-role`；发布角色 `cloudjian-gha-<工程>-role` | `cloudjian-lambda-role`、`cloudjian-scheduler-role`、`cloudjian-gha-frontend-role`、`cloudjian-gha-backend-role`、`cloudjian-gha-terraform-role` |
| GitHub 仓库 | `cloudjian-<工程>` | `cloudjian-frontend`、`cloudjian-backend`、`cloudjian-infra` |
| SSM 参数 | `/cloudjian/<key>` | `/cloudjian/bucket`、`/cloudjian/api-url` |
| 部署产物前缀 | `deploy/backend/<sha>.zip` | 函数代码包按 commit 哈希命名，不可变 |
| Terraform 工作区 | `<region>` | `tokyo` |

> 注：S3 桶名全球唯一，若 `cloudjian-data-tokyo` 已被占用，统一追加账号短号（如 `cloudjian-data-tokyo-a1b2`），规则不变。

**环境后缀规则（v1.11 简化后取消）**：只有一个环境，资源名统一为 `cloudjian-<用途>`，**不再有 `-dev`/`-staging`/`-prod` 后缀**，第 2–11 章出现的 `cloudjian-data-tokyo`、`cloudjian-notes-api`、`cloudjian-api` 即是线上实体。SSM 参数也不带环境段（`/cloudjian/<key>`）。若日后恢复多环境，再按当时方案加后缀，不做预留。

### 13.3 代码与文件命名

| 范围 | 规则 | 示例 |
|---|---|---|
| 前端组件 | `kebab-case.tsx` | `note-editor.tsx`、`conflict-diff-panel.tsx`、`language-switcher.tsx` |
| 前端状态/工具 | `kebab-case.ts` | `note-store.ts`、`presign-upload.ts`、`i18n.ts` |
| 语言包 | `<lang>/<namespace>.json` | `zh-CN/errors.json`、`ja-JP/editor.json` |
| 后端 Python 模块 | `snake_case.py` | `notes_handler.py`、`parquet_store.py`、`error_codes.py` |
| Python 包根 | `cloudjian` | `backend/cloudjian/` |
| 基础设施文件 | 按资源分文件 | `s3.tf`、`cloudfront.tf`、`observability.tf` |
| 环境变量 | `CJ_` + 大写下划线 | `CJ_BUCKET`、`CJ_REGION`、`CJ_USER_POOL_ID` |
| 本地/云端键值 | `cj:` 前缀 | `cj:token`、`cj:theme`、`cj:lang`、`cj:last-dir` |
| 错误码 | 全大写下划线 | `NOTE_NOT_FOUND`、`SHARE_FORBIDDEN` |

### 13.4 一致性收益

- CloudWatch 日志按 `cloudjian-*` 前缀即可整体筛出所有调用
- Terraform 资源名由变量拼接，避免手写拼错
- 看到 `cloudjian-share-api` 就能定位到第 7 章，命名即文档
- 单环境，无「新开测试环境」的标准动作；若临时演练，按 12.8 另起一套栈并在结束时连同 SSM 参数销毁

---

## 14. 承载能力与升级路径

### 14.1 承载上限测算

- 单篇索引记录约 300–400 字节（含 `note_id`、`lang`）
- 单用户 1000 篇 → `index.parquet` 约 40–80KB；10000 篇 → 约 400–800KB
- 搜索分片：每 256 篇一片，1000 篇约 4 片，单片未压缩约 800KB
- 100 人 = 100 份独立索引，写入天然分散
- **受 6.3 服务端搜索改造约束**：`shard_count=32` × 每片 256 篇 = 8192 篇/用户，5000 篇（C 档人均）在容量内，单用户 5000 篇以内响应稳定；超过 8192 篇后需提高分片并行度或引入 OpenSearch
- 阈值：单用户 > 2 万篇或总用户 > 500 人时，Lambda 内存与 S3 LIST 开销开始显现

### 14.2 升级路径

| 阶段 | 触发条件 | 动作 | 成本影响 |
|---|---|---|---|
| 一 | 并发写入加剧、复杂查询变慢 | 元数据迁 DynamoDB，替代 `index.parquet` | +$1–3/月 |
| 二 | 需要邮箱验证 / 密码找回 / MFA / 威胁防护 | Cognito 升级到 **Plus**（无免费额度） | +$0.02/MAU（100 人约 $2/月）+ SNS/SES |
| 三 | 单用户笔记超 2 万篇、搜索变慢 | 引入 OpenSearch | 最小实例约 $15–20/月，成本跳一个数量级 |

> 每次升级前必须单独出一份成本对比，不接受「平滑增强、成本不变」的模糊说法。

---

## 15. 审核整改记录

依据《云笺 CloudJian 方案审核报告 · 风险与成本》（2026-11-25）。

### 15.1 P0 阻断项（4 项，3 项彻底整改 + 1 项缓解）

| ID | 缺陷 | 整改落点 | 验收标准 |
|---|---|---|---|
| R1 | CloudFront 路径白名单设计错误，私有数据可能整桶匿名可读 | 11.1 三道闸：Bucket Policy 精确两条前缀 + CloudFront Function 白名单 + CI 匿名穿透测试 | 真实 key 的匿名请求全部 403 |
| R2 | JWT 本地验签，禁用/降权/改密无法即时生效 | 4.6 每请求查注册表（60s 缓存）；4.7 用户用 AccessToken 自助 `GlobalSignOut`、管理员重置由 Lambda 代调 | 禁用用户 ≤60 秒内 401（**缓解而非即时**，见 15.5） |
| R3 | `custom:role` 存在自助提权路径且属性不可变 | 4.3 改用 Cognito Groups + App Client 写入属性最小化为空 + 服务端注册表为准 | 普通用户改角色被拒 |
| R4 | `note_slug` 全局主键与「同目录唯一」冲突 | 5.2 引入 ULID `note_id` 作主键，slug 仅作文件名；版本按 `note_id` 归档 | 跨目录同名互不干扰、版本不串篇 |

### 15.2 P1 严重项（6 项，5 项彻底整改 + 1 项缓解）

| ID | 缺陷 | 整改落点 |
|---|---|---|
| R5 | 全文搜索全量下发正文，撞 10MB/6MB 限制 | 6.3 改服务端搜索 + 分片索引，只返回命中分页与短摘要 |
| R6 | ZIP 同步内存打包，撞 413 / 29 秒超时 | 6.6 ZIP 写 `exports/` + 预签名 URL + 1 天生命周期；大批量异步轮询 |
| R7 | 元数据双写、跨索引同步无事务、Schema 缺 `shared_with` | 7.1 单一数据源；7.2 共享关系改为共享者命名空间内单写者文件，目录共享不展开；5.3.2 补全字段 |
| R8 | 冲突检测 TOCTOU 与 ETag ABA | 5.3.5 / 7.5 所有写统一 `If-Match` + 单调 `version`；区分 412/409/404；开启 S3 Versioning。**TOCTOU 已消除，ABA 改为「已缓解」**：ETag 反映内容，A→B→C 改回原内容时条件写仍通过，VersionId 只能事后追溯，工程上接受（见 15.5） |
| R9 | Parquet + Layer 过度工程 | 5.3.1 撤回「列裁剪」等不实收益表述；补 5.3.6 三项运维工具；**用户决定保留 Parquet，代价与切换路径记录见 15.3** |
| R10 | 全量逐对象操作超时且留半完成状态 | 6.1 目录移动改可续跑批量任务；8.3 新增反向引用表 |

### 15.3 决策记录：保留 Parquet

审核建议把索引改为 gzip JSON（40–80KB → 10–20KB），零 Layer、零冷启动、控制台可查看、可人工修数据、无 schema 版本问题。**用户已确认采用 Parquet**，理由：

- 已通过 5.3.6 补齐运维工具，二进制不可读的痛点有兜底
- 已撤回「列裁剪」的不实收益表述，不再以性能为由选它
- 保留 Parquet 的真实动机是技术选型偏好与离线分析能力，属于产品决策而非架构必需

**代价**：CI 多一条 Layer 编译链路、冷启动 +约 100ms、Schema 演进需谨慎、故障时需下载-改-上传。

**决策结论**：保留 Parquet，接受上述代价。后端工程承担 Layer 的构建与版本发布（12.3、12.4），infra 不管理任何 Lambda 资源。若后续可运维性成为主要痛点，切换成本约为「改一个存储适配层 + 删 Layer」，不影响其余设计。

### 15.4 P2 / P3 处理

| ID | 问题 | 处理 |
|---|---|---|
| R11 | 文档内部矛盾 9 处 | 全部消解：单桶/双桶（5.1 已分离 state 桶）、列裁剪（5.3.1 撤回）、全量下发（6.3 改服务端）、`shared_with` 缺字段（5.3.2 补）、slug 主键（5.2 改）、默认 Behavior（11.1 补）、Refresh Token 不可设 0（4.2 改述）、撤销不生效（4.6 补）、IaC/CI 争抢（12.3 定契约） |
| R12 | IaC 与 CI 冲突、权限过宽、无监控 | 12.3 归属契约 + 12.5 三角色拆分；12.7 日志保留 30 天、Budgets、Versioning、备份、告警；各流水线内置穿透测试与集成测试 |
| R13 | 登录遗漏 `NEW_PASSWORD_REQUIRED` | 4.2 第 2 步补齐 challenge 流程；改用 SRP 避免明文密码 |
| R14 | 私有图语义与刷新机制未定义 | 8.1 改用 **S3 预签名 URL**（TTL 5 分钟）+ 静默重签 + 前缀隔离（v1.6 修正：CloudFront 签名 URL 与 11.1 白名单冲突，见 15.5 N1） |
| R15 | 命名规范 3 处 | 13.1 修正 Hosted UI 域名与 User Pool 名称的区别；13.1 成本归集改 Tag 激活；12.1 改 S3 原生锁文件 |
| R16 | 成本与升级表述不严谨 | 12.8 三档算式模型（v1.6 按 PUT/GET/LIST 拆分复核）；14.2 升级影响写明成本跳变 |

### 15.5 复审整改记录（v1.5 → v1.6）

依据《v1.5 复审报告 · 整改验证与成本节约》（2026-11-25）。复审确认 v1.0 的 4 项 P0 与 6 项 P1 基本闭环，同时指出 2 处实现阻断与 2 项击穿预算的成本缺陷。

| ID | 缺陷 | 严重度 | v1.6 整改落点 |
|---|---|---|---|
| N1 | 私有图走 CloudFront 签名 URL，与 11.1 白名单互斥，私有图 100% 不可用 | P0·功能 | 8.1 改为 S3 预签名 URL（TTL 5 分钟 + 静默重签），私有图不经 CloudFront；11.1 两道闸不变，另注明「private 本无 CDN 入口」 |
| N2 | 后端 OIDC 角色缺 `iam:PassRole`、`s3:GetObject`、SSM 读取过窄、契约校验读权限 | P0·流水线 | 12.5 补齐四项权限；执行角色补 `logs:CreateLogGroup`；删除 12.4「API ID 不存在则跳过」分支 |
| N4 | 开启 Versioning 但无非当前版本生命周期，旧版本永续累积 | P0·成本 | 12.7 增加 `NoncurrentVersionExpiration: 7d` + `NoncurrentVersionsToRetain: 3` + `AbortIncompleteMultipartUpload: 7d`；笔记正文放宽 30 天（该条 v1.7 已删除，见 15.6 P2-3） |
| N5 | 7.2「共享给我」遍历全库 LIST，单项超基准档总预算 | P0·成本 | 7.2 改为集中收件箱索引 `users/_share_inbox.parquet`（1 次 GET + 15 分钟缓存 + 每日对账） |
| N3/N6–N8 | 请求费低估 40–50%、存储口径不自洽、漏列 LIST / CI 分钟数 / 密钥管理 | P1·成本 | 12.8 重写为 PUT/GET/LIST 拆分行 + 当期/非当前版本拆分行 + CI 分钟数与杂项行，稳态 $0.98 / $2.07 / $4.13 |
| N10 | R8 的 ABA 只能事后追溯 | P1·措辞 | 15.2 与 16.2 改为「已缓解」，不再按「彻底解决」设计验收 |
| N11 | 分片并发 412、jobs 轮询、目录权限多次 GET、`WriteAttributes` 空集、IdToken 调 API | P1·细节 | 6.3 分片按 `note_id` 哈希固定归属 + 指数退避；4.2 统一用 AccessToken 调 API；4.3 补 challenge 阶段属性例外说明；7.3 权限登录时预计算缓存 |
| N9 | 新引入 11 处文档矛盾 | P1·文档 | 全部消解：3.2 残留「infra 声明函数骨架」、5.2 `permissions` 字段、5.3.2 三个共享字段、2.1「即时失效」、4.7 自助签出 Token 类型、5.1/12.3 `exports` 路径、13.2 别名规则、12.4 跳过分支、12.6 NAT 报价、`pref_lang` 双写、ESLint 白名单 |

**复审保留意见（不在本轮修改）**：

- 保留 Parquet 与成本节约不冲突，唯一真实云费是 Layer 编译的 CI 分钟数，已用 lockfile 哈希 + S3 产物缓存压到 $0
- `rebuild_index.py` 支持按用户/目录限定范围重建，避免故障时全库 LIST
- 建议定期清理旧 Layer 版本（占函数存储配额但不计费）

### 15.6 第三轮整改（v1.6 → v1.7）

| ID | 缺陷 | 严重度 | v1.7 整改落点 |
|---|---|---|---|
| P0-1 | 生命周期规则前缀含 `*`，S3 不支持通配符，四条规则全部静默失效 | P0·成本 | 12.7 改为按对象标签 `cj:retention=30d/1d` 过滤；6.5/6.6 写明写入侧打标签；删除笔记正文的 30 天放宽规则（P2-3）；新增「造数命中测试」验收，不接受 apply 成功即通过 |
| P0-2 | `cloudjian-lambda-role` 缺 Cognito 管理动作，管理后台四项功能全 AccessDenied | P0·功能 | 12.3 执行角色补 `AdminCreateUser`/`AdminAddUserToGroup`/`AdminRemoveUserFromGroup`/`AdminDisableUser`/`AdminEnableUser`/`AdminResetPassword`（限本用户池） |
| P0-3 | SPA 路由与白名单冲突：根路径被 403、`/login` `/notes` `/admin` 不匹配 `web/` 前缀、无 404 回退 | P0·功能 | 11.1 Function 增 SPA 入口 rewrite；~~分发加 `CustomErrorResponses`~~（v1.7.1 已撤销，与函数 403 互斥，见 15.7 F2）；10 章统一 `base=/web/` 与 Router 语义；12.4 冒烟改为 Function 行为矩阵 |
| P1-4 | 数据桶从未配 CORS，直传与 canvas 缩略图必失败 | P1·功能 | 8.2 与 12.1 补 `aws_s3_bucket_cors_configuration`，`ExposeHeaders=[ETag]` |
| P1-5 | 改密后 ≤60 秒失效缺机制（注册表只存 status/role） | P1·安全 | 5.3.3 增 `password_changed_at`；4.6 增 `auth_time` 比对；4.7 开 `EnableTokenRevocation` |
| P1-6 | 定时任务无归属与目标函数 | P1·运维 | 12.3 增第 6 个函数 `cloudjian-maintenance-api`；infra 建 EventBridge Scheduler 两条规则，目标为固定名 ARN |
| P1-7 | backend 角色 `ssm:PutParameter` 范围过宽 | P1·权限 | 12.5 收窄到 `release/*` 与 `lambda-*` |
| P2-1 | 「每片 ≤256 篇」与固定哈希映射矛盾 | P2·文档 | 6.3 固定 `shard_count=16`，扩容归入 14.2 一次性重建 |
| P2-2 | 分片搬移 20 秒预算 vs 函数 20 秒超时，零余量 | P2·可靠性 | 6.1 预算降为 15 秒；12.3 函数超时 25 秒 |
| P2-3 | 笔记正文非当前版本「放宽至 30 天」方向反了 | P2·成本 | 12.7 删除该规则，历史统一由 `versions/` 承担 |
| P3 | 13.2 别名重复行、每日/每周混用、12.5 权限重复、12.8 存储口径、5.2 `share_state`、8.1「custom policy」术语 | P3·文档 | 逐条消解：删重复行、定时统一为每周（索引抽查除外）、12.5 合并表述、12.8 存储改 6.5/10/17.5 GB 并给区间、5.2 移除 `share_state`、8.1 改「签名参数绑定具体 key」 |

**本轮决策记录**：P0-1 在报告给出的两条路线（标签过滤 / 把 trash、versions、exports 提升为桶顶层前缀）中选**标签过滤** —— 不改目录结构、不动 IAM 前缀授权、迁移面为零，代价是写入侧必须记得打标签，已在 6.5/6.6 与验收项中固化。

### 15.7 第四轮整改（v1.7 → v1.7.1）

| ID | 缺陷 | 严重度 | v1.7.1 整改落点 |
|---|---|---|---|
| F1 | 12.7 在标签化新方案之后仍留着 v1.6 旧文案（含笔记正文「放宽 30 天」与旧参数名 `NoncurrentVersionsToRetain`），照此实现会同时落两套规则 | P1·文档 | 删除整段残留；全文统一 Terraform 参数名 `newer_noncurrent_versions`；只保留标签化两条 + 空 filter 一条 |
| F2 | CustomErrorResponses 403→200 与「函数对私有路径 403」互斥，深链与闸 3 断言必坏一边 | P1·设计 | 撤销任何 403/404 映射；Function 增「无扩展名路径 catch-all rewrite」；私有路径终态 403；12.4 冒烟改为完整行为矩阵 |
| F3 | 回收站移动是 CopyObject，默认 `TaggingDirective=COPY`，对象永不带 `cj:retention=30d`，30 天清理整体失效 | P1·成本（静默） | 6.5 增 `copy_with_retention()` + `TaggingDirective=REPLACE`；6.1 目录搬移明确不加 TTL 标签；17.9 CI 门禁扩展至 `copy_object`/`upload_file`；验收补 `get-object-tagging` |
| F4 | terraform-role 无 `scheduler:*`，新增调度建不出来；调度执行角色未定义 | P1·流水线 | 12.5 补 7 个 scheduler 动作 + `iam:PassRole`（限调度角色）；13.2 增 `cloudjian-scheduler-role`；12.3 定义其信任策略与最小权限；12.4 说明 maintenance 不挂 API GW |
| F5 | 只设 IdToken 20 小时，AccessToken 仍默认 60 分钟，每小时被踢 | P2·功能 | 1 章 / 4.2 / 10 章统一「双 Token 20 小时，以 AccessToken `exp` 为准」 |
| F6 | 收件箱索引实为多写者热对象；「每周对账省 CI 分钟」理由不成立 | P2·一致性 | 7.2 改写语义、补「3 次耗尽 → 500 + 告警」；对账改每日，周更只留 Actions 侧任务 |
| F7 | 公开图经 CDN 缓存可能丢失 ACAO，canvas 缩略图间歇失败 | P2·功能 | 8.2 公开图 Behavior 转发 `Origin` 进缓存键；CI 冷/热缓存两次断言 ACAO |
| F8 | `shard_count=16`（4096 篇）与 14.1 / C 档 5000 篇矛盾 | P3·容量 | 6.3 改 32（8192 篇），14.1 同步 |
| F9 | `auth_time`（秒）与 `password_changed_at`（毫秒）直接比较会失准 | P3·实现 | 4.6 明确统一存秒（或比较前 `//1000`），列为第一条单测用例 |
| F10 | `EnableTokenRevocation` 对本地 JWKS 验签无效，「双保险」名不副实 | P3·措辞 | 4.7 降级为「换 Token 的接口会被 Cognito 拒绝」，真正兜底写明是 `auth_time` 比对 |
| F11 | 预签名 PUT 无法服务端强制大小上限 | P3·实现 | 8.2 给两条路线，默认「前端限 + 登记 `HeadObject` 校验后删除」，并明确不声称服务端强制 |
| F12 | 4.6 两条都编号 3.；缺 `ExpiredObjectDeleteMarker`；验收未覆盖 Copy 路径 | P3·文档 | 编号修正；空 filter 规则加 `expired_object_delete_marker=true`；验收补 Copy 用例 |

**本轮结论**：报告第 5 节建议「v1.7.1 只做 F1–F4 后冻结」，v1.7.1 把 F5–F12 也顺手收了（均为文字/配置级）；v1.8 随后执行了被推迟的 API Gateway 换 HTTP API，成本降至 ≈$0.61 / $1.38 / $2.67（v1.9.1 复核修正后）。

### 15.8 v1.8 修订：API 网关换 HTTP API

| 项 | 变更 |
|---|---|
| 网关类型 | REST API → **HTTP API**（`cloudjian-api`，stage `dev`） |
| 计价 | $3.50/百万 → **$1.00/百万**；A/B/C 档 $0.07 / $0.13 / $0.26（C 档按 26.4 万次；v1.8 当时按 30 万次算作 $0.30，为历史值） |
| 路由模型 | 资源树 + 方法 → 路由键（`GET /notes`、`PUT /notes/{id}`），8 组路由见 12.1 |
| 集成超时 | 29 秒 → **30 秒**；Lambda 仍 25 秒，余量从 4 秒变 5 秒 |
| 集成授权 | `add-permission` 的 `SourceArn` 到 `api-id/*` 即可（可选细化到路由） |
| 负载上限 | 10MB 不变，6.3/6.6 的规避设计无需改 |
| 鉴权 | 仍用 Lambda 中间件（需查注册表判 `status`/`role`/`auth_time`）；可额外挂原生 JWT 授权器做前置过滤（**v1.9 已执行，见 15.9**） |
| 功能影响 | 无。未用 API Key / Usage Plan / 网关缓存 / WAF / 请求校验器 / 流式响应 |
| 成本影响 | 明细合计 $0.84 / $1.84 / $3.76（v1.7.1 口径）→ **$0.61 / $1.38 / $2.67**（v1.9.2 含日志归零与 C 档请求数修正）。区间统一写作 $0.55–0.67 / $1.24–1.52 / $2.40–2.94 |

**代价记录**：HTTP API 的治理能力弱于 REST（无请求校验器、无 API Key、无网关缓存、无原生 WAF 集成、日志字段略少）。这些能力当期一个都没用；若日后需要 WAF 或请求校验，需评估「CloudFront + WAF」或退回 REST，成本会回到 $3.50/百万档。

### 15.9 v1.9 修订：网关 JWT 授权器

| 项 | 结论 / 变更 |
|---|---|
| 是否值得加 | 加。定位是「零成本纵深防御」，不是省钱项 |
| 配置 | issuer 为用户池 URL；**audience 填 App Client ID**（AccessToken 无 `aud`、回退校验 `client_id`）；identity source `$request.header.Authorization`；不声明 scope |
| 实际拦截 | 签名/`kid`/算法、`iss`、受众、`exp`/`nbf`/`iat` |
| 拦不住 | `token_use`、禁用状态、改密旧 Token、`GlobalSignOut` 后的 JWT → 全部留在 4.6 中间件 |
| 唯一真风险 | ID Token 的 `aud` 也是 Client ID，可合法过网关 → 4.6 增第 6 条，把 `token_use=access` 定为硬门槛 |
| maintenance | 不挂授权器、不暴露到 HTTP API，由 Scheduler 以 IAM 直调 |
| 边界 | 无 WebSocket，`$connect` 议题不适用；预检由网关应答，Lambda 不重复输出 CORS 头 |
| 成本 | 授权器免费、被拒请求不计 Lambda；**账单节省 $0**（被拒请求仍计 HTTP API 费，且 Lambda 本来在免费额度内）—— 收益是并发、冷启动与日志噪声，不并入成本模型（V6） |
| 顺带补齐 | **API 侧 CORS**（此前只有 S3 桶 CORS）—— 缺它浏览器跨域调 API 会在预检阶段失败 |

### 15.10 v1.9.1 修订：第五次审核整改（G1–G16）

| ID | 缺陷 | 严重度 | 整改落点 |
|---|---|---|---|
| G1 | 12.1 选型表「授权器可选／本期仍用 Lambda 中间件」与同节的网关鉴权整节互斥 | P1·文档 | 选型表「鉴权」行改为「双层：网关授权器 + Lambda 中间件」，并注明是叠加不是二选一；15.8 的 v1.8 时态行加注「v1.9 已执行」 |
| G2 | 网关 401 可能不带 ACAO（授权器在集成前拒绝、HTTP API 无 gateway responses、业务 API 不经 CloudFront） | P1·功能 | 12.1 增「已知风险」小节：验收带 `Origin` 断言 401+ACAO；前端跳登录改为「本地 `exp` 预判 + 401/网络错误兜底」两层；10 章同步 |
| G3 | 「中心值」前后口径不同（区间中点 vs 明细合计），降幅对不上 | P1·成本 | 固定「中心值 = 明细逐项加总」= $0.68 / $1.51 / $3.01（v1.9.2 复核后为 $0.61 / $1.38 / $2.67，见 15.11）；区间为其 ±10%；说明因仅 API GW 一行变化，合计降幅即单项降幅 $0.16 / $0.33 / $0.75（该表述在 15.11 复核后已修正为两项修正叠加） |
| G4 | 「省一次 JWKS 拉取」与「保留本地验签」互斥；漏挂路由无自动化兜底 | P1·安全 | 明确选方案 A（信任 `authorizer.jwt.claims`、不做本地验签），删除互斥表述；补 `get-routes` 门禁（8 组路由 `JWT` + `AuthorizerId` 与 SSM 一致、默认 `NONE` 高危值）；中间件断言 `requestContext.authorizer` 缺失即 401；补「不含 authorizer 的 event」单测 |
| G5 | 标「东京区」却用美东目录价 | P2·成本 | 12.8 注明单价来源；给东京口径复核值（API GW ≈$0.09/$0.17/$0.39、实省 ≈$0.20/$0.39/$0.89 —— **均为 30 万请求时的 v1.9.1 口径，26.4 万口径现值见 12.8**） |
| G6 | 未写 `$default` 路由陷阱；「避免重复头」机制描述不准 | P2·功能 | 12.1 增硬约束「不创建 `$default` 路由；若必须则显式 `OPTIONS /{proxy+}` `NONE`」；措辞改为「网关忽略集成返回的 CORS 头」；冒烟补 OPTIONS 预检 |
| G7 | 用量假设「每天」与明细（22 工作日）不一致；`_refs.json` 与 8.3 条件写矛盾；CloudWatch Logs 缺依据 | P2·成本 | 12.8 声明按 22 工作日折算；PUT 行注明 `_refs.json` 为条件写、按 4 次可再省 ≈$0.06/$0.17/$0.33（未并入）；补日志 ingest 估算 |
| G8 | HTTP API 按 512KB 增量计量，6.3「响应 ≤1MB」可能翻倍计费 | P2·口径 | 6.3 改为「≤512KB」并注明计量规则 |
| G9 | 「声明 scope 需建 Resource Server」理由不成立 | P2·加固 | 12.1 Scope 行改写：SRP 直登的 AccessToken 默认带 `aws.cognito.signin.user.admin`、ID Token 无 scope，声明 `authorizationScopes` 即可拒 ID Token、零成本；先实测再启用 |
| G10 | 冒烟断言用 REST 时代的 `x-amzn-errortype`；未说明测试账号来源 | P3·验收 | 改为断言响应体 `{"message":"Unauthorized"}` / `WWW-Authenticate`；测试账号由 infra 预置的测试用户在 CI 中以 Secrets 注入 |
| G11 | 15.9「5% 坏 Token 省 $0.01–0.05」与 Lambda $0 矛盾 | P3·措辞 | 改为「账单节省 $0；收益是并发、冷启动与日志噪声」，与 12.1 一致 |
| G12 | 修订说明出现未定义编号「F-新1」；15.8/15.9 标题都叫「第五轮」 | P3·文档 | 删编号引用；标题改为「v1.8 修订」「v1.9 修订」 |
| G13 | 3.1 链路图未体现 HTTP API 与 JWT 授权器 | P3·文档 | 图改为「HTTP API（JWT 授权器）→ Lambda（中间件）」两层 |
| G14 | `apigateway:*` 未限资源 | P3·权限 | 12.6 记取舍：V2 资源 ARN 含随机 `api-id`，可收窄为 `arn:aws:apigateway:ap-northeast-1::/apis/*`；单人项目接受全账号通配并备查 |
| G15 | `/cloudjian/jwt-authorizer-id` 无自动化消费者 | P3·文档 | 与 `get-routes` 门禁合并，作为断言期望值来源 |
| G16 | 前端 ETag 传递位置未定义，`AllowHeaders` 含 `if-match` 却无对应说明 | P3·接口 | 12.1 明确：ETag 走请求头 `If-Match`，Lambda 原样透传给 S3；响应 `ETag` 头回传新值，故 `ExposeHeaders=etag` |

**本轮结论**：审核建议「只做 G1–G4 + 成本口径，然后冻结设计」。本版按其建议完成 G1–G4 与 G3/G5/G7/G8 的成本口径统一，G5–G16 的其余项一并在文档层收口；**成本模型自此冻结**，唯一未并入的省钱项是 `_refs.json` 条件写（8.3 已定义为条件写，代码照文档实现即可拿到 ≈$0.06/$0.17/$0.33）。

### 15.11 v1.9.2 修订：整改验证收口（V1–V10）

| ID | 问题 | 严重度 | 整改落点 |
|---|---|---|---|
| V1 | 12.1 要求「401 + ACAO」硬断言，而官方机制下授权器在集成前拒绝、CORS 头只加在集成响应上 → CI 必挂 | P1·验收 | 改为**硬断言 `status=401`、ACAO 仅记录**；明确「无 ACAO 属预期」，并要求确认前端第 2/3 层兜底已生效；与 12.4 步骤 5 完全对齐 |
| V2 | 新补的日志算式（0.4/0.8/1.8 GB × $0.76）与表内 $0.07/$0.13/$0.30 差 4–5 倍，且漏了 5GB/月永久免费额度 | P1·成本 | 该行改 **$0**，注明 5GB 永久免费额度（估算 0.4/0.8/1.58 GB 全在额度内）；合计、区间、1 章成本目标、含审计增强项四处同步重算 |
| V3 | 选方案 A 后，4.6 第 3/5 条与 4.7 仍写「本地 JWKS 验签」「JWKS 缓存 1 小时」 | P1·实现歧义 | 三处统一改为「网关 JWT 授权器验签」；4.6 第 5 条保留 claims 二次比对但删掉 JWKS 缓存半句；明确「Lambda 不碰 JWKS」 |
| V4 | 「区间 = 中心值 ±10%」与表内 B/C 端点、声明宽度对不上 | P2·成本 | 端点严格按 ±10% 重算（中心值修正后为 $0.55–0.67 / $1.24–1.52 / $2.40–2.94），同步 1 章与 15.8 |
| V5 | C 档 30 万请求与 22 工作日口径不符（应为 26.4 万） | P2·口径 | 假设、API GW 行（C 档 $0.26）、日志量、东京换算（$0.34 / 实省 $0.78）四处统一为 26.4 万 |
| V6 | 15.9 仍写「省 $0.01–0.05/月」，与 12.1「账单节省 $0」互斥 | P3·文案 | 15.9 同步改为「账单 $0；收益是并发、冷启动与日志噪声」 |
| V7 | 12.2 参数表把 `jwt-authorizer-id` 读取方写「诊断用」 | P3·文案 | 改为「infra CI `get-routes` 门禁」，用途是断言期望值来源 |
| V8 | 「测试账号由 Secrets 注入」只写在整改记录，12.4 正文没落地 | P3·验收 | 12.4 步骤 5 补：infra 预置 `cloudjian-ci-test-user`，流水线 SRP 登录取 Token、用完 `GlobalSignOut` |
| V9 | 文档头降幅未标「单项」；「网关拦不住 `token_use`」在启用 scope 后不成立 | P3·文案 | 头部标「API Gateway 单项」；该句改为条件式「未声明 scope 时拦不住」，并注明启用 scope 后降为第二道防线 |
| V10 | 15.8 用区间下限（0.84/1.86/3.81），12.8 用明细合计（0.84/1.84/3.76） | P3·成本 | 全部统一为明细合计 $0.84 / $1.84 / $3.76 → $0.61 / $1.38 / $2.67 |

**冻结结论**：架构决策（HTTP API + 网关 JWT 授权器 + 方案 A + `get-routes` 门禁 + scope 可选加固）已稳定，V1–V10 属文档/配置级收尾。仍留的实测项见 15.12 末尾。

### 15.12 v1.9.3 修订：收口验证整改（W1–W8）

| ID | 问题 | 严重度 | 整改落点 |
|---|---|---|---|
| W1 | 把「5GB 永久免费额度覆盖 Lambda 日志」写成定论，而官方计费页有反证（Lambda 日志自 2025-05 归为 Vended Logs），上一轮点名的确认项被跳过 | P1·成本依据 | 12.8 日志行改**双口径**：①覆盖 → $0（本表采用，中心值 $0.61/$1.38/$2.67）；②不覆盖 → $0.30/$0.60/$1.20，合计 $0.91/$1.98/$3.87（含审计 3.2/6.4/14.9），仍 < $5；删掉「当前不会触发」绝对措辞；1 章成本目标同步注明；实测项补「首月账单确认 CloudWatch Logs 是否计费」 |
| W2 | V5 只扫了 12.8 表内，表外仍有 4 处 30 万口径，C 档单项降幅出现 $0.75 / $0.79 / $0.66 三个值 | P1·口径 | 12.1 选型表 C 档改 **$0.26**；15.8 计价行改 $0.26 并标注 v1.8 的历史值 $0.30；文档头降幅加注「v1.8 当时按 30 万请求，26.4 万口径为 $0.66」；12.8 关键结论 REST 基准改 **$0.92**、单项降幅改 **$0.66**（消除 30 万 REST 减 26.4 万 HTTP 的混口径减法） |
| W3 | 存储两行与用量假设表互相打架：假设表说 6.5GB「已含 3 份旧版」，明细却按当期 + 非当前两段收费；非当前行「≈0.1 GB」与金额（$0.02/$0.03）差 8–12 倍 | P2·口径 | 假设表改「总存储 · **当期对象**（非当前版本另计）」；非当前行说明改 **≈0.8 / 0.8 / 1.2 GB**（按金额 ÷ $0.025 反算）；金额不动，合计不受影响 |
| W4 | 12.4 步骤 5 仍写「断言 ACAO 是否存在」，措辞含糊且有硬断言嫌疑 | P3·验收 | 改为「断言 `status=401`；ACAO 只记录、不作阻断项（V1/W4）」 |
| W5 | 12.8 与 15.8 把 v1.9.2 的中心值挂在 v1.9.1 名下 | P3·版本 | 两处版本标注改 **v1.9.2** |
| W6 | 15.10 的 G5 落点仍是 30 万口径（$0.39 / $0.89），与「四处统一」矛盾 | P3·历史记录 | 加注「v1.9.1 口径，26.4 万口径现值见 12.8」，历史记录保留原值 |
| W7 | 「拿 ID Token 也能过网关」「授权器无法区分 access/ID」为绝对表述 | P3·口径 | 两处加限定「**当前未声明 `authorizationScopes` 的配置下**」，与 V9 的条件式一致 |
| W8 | 4.6 引言「本地验签无法感知」在方案 A 下易被回读成仍要本地验签 | P3·措辞 | 改为「仅凭 JWT 自包含的信息（含网关的离线验签结果），无法感知……」 |

**仍留的实测项（冻结后进实现阶段逐项验证）**：

1. SRP 登录返回的 AccessToken 的 `scope` 实际值 → 决定是否启用 `authorizationScopes`
2. 网关 401 的响应头与 ACAO 实测 → 确认 12.1 的软口径与前端两层兜底
3. **首月账单确认 CloudWatch Logs 是否计费** → 回填 12.8 日志行（$0 或 $0.30/$0.60/$1.20）
4. 生命周期造数命中（含 Copy 路径进 trash）与 31 天清理
5. Function 行为矩阵（`/` `/login` 200、`/users/*` 403、`/web/missing.js` 404）
6. 公开图 ACAO 冷/热缓存断言
7. 网关 401 前的 `OPTIONS` 预检 200 + `get-routes` 授权类型断言

**冻结判断**：W1 是「把未决前提写成定论」、W2 是「旧数字没扫出 12.8」，两者都不改变任何设计选择；14 章与 12.8 的架构与成本口径稳定，**v1.9.3 为设计冻结版**，直接进入编码。

### 15.13 v1.10 修订：第 17 章决策落定与分支即环境

| # | 决策 | 影响面 | 落点 |
|---|---|---|---|
| D1 | 共享目录 = 一条虚拟目录 | 只改前端展示与 7.3 语义，后端 shares 模型不动（本就是一条记录） | 7.3 |
| D2 | 回收站还原树形 | 新增恢复 job 类型；需读 `trash/` 下 `.dir_meta.json`；15 分钟缓存；重名 `-1` | 6.5、6.1 |
| D3 | 整目录导出 ZIP | 复用 `exports/` 与预签名流程，加阈值转异步 | 6.6 |
| D4 | 删除笔记联动清理公开图 | 依赖 `_refs.json` 判定；**v1.10.1 改为移入 `assets/_trash/` + 30 天标签**（不再立即物理删除，恢复后图片可回） | 8.3 |
| D5 | 管理员全局可见性开关 | 团队级配置定在 `users/_team_config.json`（5 分钟缓存）；**强制私有前置到 presign**（v1.10.1 修正） | 8.1 / 8.2 |
| D6 | 三语封版、无内容规范 | 删掉「可扩展第四语言」的暗示；`lang` 只作检索提示 | 9.1 |
| D7 | 分支即环境 CI/CD（**已被 v1.11 取代：只保留 dev 一个环境**） | 资源 ×3 环境、SSM `/cloudjian/*`、workspace ×3、OIDC 角色 3×3=9、`main` 去部署化 | 12.2/12.4/12.5/13.2/12.8；v1.11 见 15.15 |

> D7 的代价要写清：三套环境意味着三条流水线各跑三份部署（Actions 分钟数上升，main 不再部署抵消一部分；v1.10.1 已按 ≤2,000 分钟目标收敛并写入 12.8），且 dev/staging 需额外占用 S3 桶、Cognito 池与 CloudFront 分发（估算增量 $0.03–0.08/月·套）。换来的是「合并 PR 即上线、回滚只需 revert 一个分支」的可审计发布链。

---

### 15.14 v1.10.1 修订：v1.10 增量审核整改（X1–X18）

> **v1.11 提示**：本节 X2 的「跨环境残余面」与 9 条角色的前提已随「只保留 dev 单环境」失效；X1 的 `environment:` 结论仍有效，仅把 `environment:<env>` 收敛为 `environment:dev`。历史记录保留原文，以 15.15 为准。

| ID | 级别 | 问题 | 整改落点 |
|---|---|---|---|
| X1 | P1·阻断 | GitHub Environment job 的 OIDC `sub` 为 `environment:<env>`，与 12.5 原 `ref:refs/heads/<env>` 不匹配 → prod 三角色全部 assume-role 失败 | 12.5 全部改 `environment:<env>`；三环境统一声明 `environment`；删掉正文里冒号写法的 `refs/heads:<env>`；补「首次配置回读实际 sub」 |
| X2 | P1·安全 | `iam:*`/`cloudfront:*`/`cognito-idp:*`/`apigateway:*`/`logs:*`/`budgets:*` 未按环境收窄，且 state 桶共用；13.1 标签写死 `Environment=prod` | 12.5 显式列举本环境角色 ARN、独立 state 桶、日志组/预算按 `<env>` 限定；13.1 标签改 `<env>`；**宣称降级**为「五类硬隔离 + 全局服务残余面」，12.6 记录并给出独立账号演进项 |
| X3 | P1·成本 | 15.13 自认 CI ×2.5，12.8 GHA 仍 $0 / <2,000 分钟 | 12.8 重算 ≈1,300 分钟（明细见该行）、三仓 private 明示、超出按 $0.006/分钟、上限 +$6、GitHub 另设 spending limit；12.7 Budgets 标注只管 AWS |
| X4 | P1·功能 | 跨用户图片引用不可判定；软删除瞬间物理删图摧毁 D2 恢复 | 8.3 改为「移入 `assets/_trash/` + `cj:retention=30d`」，恢复时移回并去标签；私有孤儿同规则；5.1 补前缀 |
| X5 | P1·安全 | 强制私有只拦 register，文件已落 `public/`；配置位置未定且两条路都缺支撑 | 8.2 前置到 presign（400 或改写）；8.1 定 `users/_team_config.json` + 5 分钟缓存 + 条件 GET；5.1 补对象 |
| X6 | P2·矛盾 | 12.8 关键结论仍写「当期 + 非当前 ≈6.5/10/17.5」 | 改为「当期 6.5/10/17.5 + 非当前 0.8/0.8/1.2」 |
| X7 | P2·歧义 | 6.2「共享给我由 `shares/` 汇总」会踩全库 LIST；虚拟目录展开数据源未定义 | 6.2 改为只读 `_share_inbox.parquet`；7.3 补「按 `category_path` 向 owner 索引过滤分页」 |
| X8 | P2·门禁 | 恢复逻辑未入 17.9 白名单；单篇删除无 `.dir_meta.json`；未刷新共享索引 | 6.5 明确恢复写在 `storage/retention.py`；单篇按 key 反推路径；补刷新 `shares/` 与 `_share_inbox.parquet` |
| X9 | P2·成本 | CDN 失效路径未进成本，逐文件失效 C 档 $4.9–28/月 | 12.8 CloudFront 行补「按批 1 条通配失效」与免费额度口径 |
| X10 | P2·矛盾 | 9.1 仍写「预留扩展」；启发式 `lang` 无落点 | 9.1 表格改「本期不做」；9.9 补两条不做；5.3.2 写明推断规则且不回写、不校验 |
| X11 | P2·流程 | 「staging 用完 destroy」与长期分支节奏冲突，参数残留 | 12.8 改「两条非生产环境常驻」；若 destroy 必须同 PR 清 `/cloudjian/staging/*` |
| X12 | P2·参数化 | CORS `AllowOrigins`、`AWS:SourceArn`、stage、标签、首次搭建仍单环境口吻 | 12.1 stage 改 `<env>`；11.1 `SourceArn` 从 `/cloudjian/cdn-arn` 取；13.1 标签 `<env>`；12.2 补「每环境各按序一次」 |
| X13 | P3·残留 | API Gateway 行「原为 $0.23/$0.46/$1.05」混 30 万口径 | 改标历史值 $1.05 属 30 万口径，现值 $0.92 |
| X14 | P3·算术 | 0.8×0.76=0.608 却记 $0.60，B 档合计 $1.98/$1.99 不定 | 12.8 加「按分四舍五入后逐项相加」规则，并说明 $1.98 与 $6.4 的来源 |
| X15 | P3·CI | `main` 归档无 workflow；PR 评论需 `pull_request` 而只写 push | 12.4 补 `release.yml` 与 `pull_request` 触发说明 |
| X16 | P3·封版 | 17 章称无开口项，但 D5 仍「实现阶段定」；16 章未收录 D1–D7 与三环境 | 8.1 定掉配置位置；17 章改「除已记录的残余面外无开口项」；16.1/16.2 补取舍与状态行 |
| X17 | P3·文案 | 「实测增量」无算式；1 章未标只计 prod | 12.8 改「估算」并给算式；1 章成本目标注明只计 prod、不含 GHA |
| X18 | P3·细节 | 目录导出参数/共享边界未写；私有孤儿无覆盖；恢复 `-1` 与 `shares.target_dir` 未说明 | 6.6 补三选一参数与「共享目录不可导出」；8.3 覆盖私有孤儿；6.5 补 `target_dir` 同步 |

**新增实测项（并入 15.12 清单）**：⑧ 用 `assume-role-with-web-identity` 回读 Environment job 的实际 `sub`（含 2026-07-15 后 immutable subject claims 形式）；⑨ 单环境 CI 分钟数与 GitHub 账单；⑩ presign 强制私有拒绝断言；⑪ 删除笔记后图片进 `_trash` 且 30 天清理、恢复后图片可读；⑫（v1.11.1）原「三环境隔离断言」不再适用；改为断言**部署门禁生效**：直推 `dev` 的 commit（无关联 PR）必须不触发部署，关联 PR 的 merge commit 才部署（Y2）。

**冻结判断**：X1–X5 全部落定，且都属于配置/口径/拦截位置级改动，**不动资源拓扑**；本版可作为编码基线，实现阶段只需按 15.12 + 本节实测项逐条验证，无需再开全量审核。

### 15.15 v1.11 修订：取消三环境，回归单环境发布

| # | 变更 | 原（v1.10.1） | 现（v1.11） | 落点 |
|---|---|---|---|---|
| S1 | 环境数量 | dev / staging / prod 三套 | **只有 dev 一套**（dev 分支即线上） | 12.4 |
| S2 | 分支模型 | feat→dev→staging→prod→main | **feat→dev→main**；dev 合并即部署，main 只打 tag/写发布记录 | 12.4 |
| S3 | OIDC 角色 | 3 仓 × 3 环境 = 9 条 | **3 条**（每仓一条，`environment:dev`）；X1 的 `environment:` 口径保留 | 12.5 |
| S4 | SSM / workspace / state 桶 | `/cloudjian/<env>/*`、`tokyo-<env>`、每环境一个 state 桶 | `/cloudjian/*`、`tokyo`、单 state 桶 `cloudjian-tfstate-tokyo` | 12.2 / 13.2 / 5.1 |
| S5 | 资源命名 | prod 无后缀、dev/staging 加后缀 | 一律无环境后缀（`cloudjian-<用途>`） | 13.1 / 13.2 |
| S6 | 跨环境残余面 | 全局服务无法按环境收窄，列为残余风险 | **整段消解**；新风险是「合入 dev 即改线上」，由部署门禁控制（Y2：Free 私有仓无分支保护） | 12.6 / 16.1 |
| S7 | CI 分钟数 | ≈1,300 分钟/月 + 上限 $6 | **≈1,040 分钟/月 → $0**；GitHub spending limit $10 兜底 | 12.8 |
| S8 | 预发能力 | staging 承担上线前验收 | **无预发环境**：破坏性变更（桶策略/生命周期/权限）先在 dev 造数小范围验证，或临时起演练栈后连同 SSM 参数销毁 | 12.4 / 12.8 |

**代价与底线**：取消三环境省掉的是资源与权限复杂度，不是风险本身——风险从「跨环境越权」转移到「直接改线上」。因此 `dev` 的合并纪律 + 部署门禁（未关联已合并 PR 的 commit 不部署）是硬要求，12.4 的三仓冒烟步骤是上线门禁、不能裁剪；原「分支保护」表述已按 Y2 修正（Free 私有仓不具备该能力）。**当前尚未部署任何资源，无需迁移**；本节为设计变更，不涉及数据搬迁。

### 15.16 v1.11.1 修订：单环境增量审核整改（Y1–Y10）

| ID | 级别 | 问题 | 整改落点 |
|---|---|---|---|
| Y1 | P2·阻断 | 12.4 未硬性要求凭证 job 声明 `environment: dev`；push 未声明变 `ref:refs/heads/dev`、PR 未声明变 `pull_request`，均不匹配信任策略 → 首次部署与 PR plan 100% assume-role 失败 | 12.4 增「`environment` 声明是硬约束」：凡需 AWS 凭证的 job（三仓部署 + infra 的 PR plan）必须声明；纯 lint/单测不需；不给部署角色开 `pull_request` 信任 |
| Y2 | P1·安全 | Free 计划私有仓**不支持分支保护/rulesets**，而 12.4/12.5/15.15/16.1 把它写成硬要求；与 12.8「Free 私有仓」互斥 | **最终选择：三仓 public（v1.12）** —— public + Free 即支持原生分支保护，Actions 免费。12.4 改为原生保护 + 部署侧二次校验 + 公开仓约束；单人 0 批准；12.8 改公开仓。v1.11.1 的「Free+private+部署门禁」作废 |
| Y3 | P2·权限 | frontend 角色只有 `GetParameter`，但 12.2 要它写 `release/frontend`；`release/archive` 写入方未定 | 12.5 给 frontend 加 `ssm:PutParameter`（限 `/cloudjian/release/frontend`）；12.2 明确每条 key 单一写入方，`release/archive` 归 infra |
| Y4 | P3·算术 | 「0.608→$0.61」与「合计 $1.98」不能并存（四舍五入应为 1.99） | 12.8 规则改「**截断到分**」：$0.608→$0.60、B 合计 $1.98、含审计 $6.38→$6.4，表内数字不变 |
| Y5 | P3·文案 | 6.5「恢复与搬移共用同一封装」与 6.1「两个封装」冲突，照做会让恢复 COPY 回 30d 标签（F3 复活） | 6.5 改为「共用 jobs 机制；copy 封装分开：搬移 COPY 保标签、恢复 REPLACE 去标签」 |
| Y6 | P3·歧义 | 7.3 展开虚拟目录留了两条未选方案 | 7.3 定「直接读 owner 的 `index.parquet`」——Lambda 本就有整桶读权，无需跨用户授权、无需轻量清单；缓存 15 分钟 |
| Y7 | P3·残留 | 17 章引言仍引「跨环境残余面（12.6）」（已消解）；标题停在 v1.10–v1.10.1 | 引言改「无开口项」；标题改「v1.11.1 封版」 |
| Y8 | P3·运维 | 演练栈沿用 `cloudjian-*` 命名与 `/cloudjian/*` 参数会与线上互覆盖、销毁误删 | 12.8 强制 `cloudjian-drill-*` + `/cloudjian-drill/*` |
| Y9 | P3·细节 | 失效路径含空操作 `/index.html`；生命周期表漏 `assets/_trash/`；执行角色多 `deploy/*`；契约校验载体三处不一致 | 12.4 删 `"/index.html"`；12.7 补 `_trash` 行；12.3 删执行角色的 `deploy/*`；契约校验固定在 Lambda Scheduler，12.8 分钟只算漂移 |
| Y10 | P3·评审 | 单人开发无法满足「1 人 review」（不能自批 PR） | 12.4 明确单人规则为「PR + CI 全绿 + 0 批准」，≥2 人再改 1 review + Include administrators |

**新增/更新实测项**：⑬ 声明 `environment: dev` 后回读实际 `sub`（push 与 pull_request 两种事件各一次）；⑭ 直推 `dev` 的 commit 不触发部署（部署门禁生效）；⑮ frontend 写 `/cloudjian/release/frontend` 成功、写其他 key 被拒。

**冻结判断**：Y1–Y3 已收口，Y4–Y10 为文案与细节且全部落地；架构拓扑（单环境、3 条角色、无后缀命名、单 state 桶）不变，**本版可作为编码基线**。

### 15.17 v1.12 修订：三仓公开（Y2 最终方案）

| # | 项 | 内容 |
|---|---|---|
| P1 | 可见性 | 三仓 `cloudjian-frontend` / `-backend` / `-infra` 全部 **public**；不再需要 GitHub Pro，也不再需要 spending limit |
| P2 | 门禁 | public + Free 支持分支保护：`dev`/`main` 要求「必须经 PR」「CI 状态检查通过」，勾选 **Include administrators**；单人开发 required approvals = 0；部署 job 仍保留「commit 必须关联已合并 PR」的二次校验 |
| P3 | 公开仓约束 | 禁 `pull_request_target` 带 AWS 凭证；外部协作者 PR 需批准；Actions 按 SHA 锁版本；开 secret scanning + push protection；`sub` 保持 `StringEquals` 精确匹配 |
| P4 | 暴露面处置 | 账户 ID 用 `data.aws_caller_identity` 推导不写死；桶名不靠保密，靠 BPA + OAC + 白名单；每次 apply 后 CI 跑匿名穿透断言（`users/*` 必须 403）；`terraform plan` 只贴资源计数摘要，不贴策略内容 |
| P5 | 成本 | GHA 行改「公开仓，标准 runner 免费、无额度上限」；AWS 三档不变（$0.61/$1.38/$2.67） |

**已知代价（如实记录）**：桶名、账户 ID、角色 ARN、桶策略、OIDC `sub`、CI 配置与全部设计细节长期公开；commit 历史、已删文件和 PR 讨论永久可见；攻击者可据此做定向尝试。**缓解不是「没人看」，而是策略正确 + 自动化断言 + 分支保护**。若日后新增协作者或出现定向攻击，优先手段是恢复 private（此时需 Pro）+ 或独立 AWS 账号，而非继续靠公开仓免费额度。

### 15.18 v1.13 修订：运行时基线（Python 3.14 / Node.js 24）

| # | 项 | 内容 |
|---|---|---|
| Z1 | 后端 | 6 个 Lambda 全部 `python3.14`；Layer 由 `public.ecr.aws/lambda/python:3.14` 构建，**runtime 与 Layer 同版本是硬约束**（跨版本会 `ModuleNotFoundError` 或 C 扩展 ABI 不匹配） |
| Z2 | 前端 | 构建期 Node.js 24 LTS；`.nvmrc`=`24`、`engines` 锁 `>=24 <25`、CI `node-version: 24`，三处一致防“本地能跑 CI 挂” |
| Z3 | 缓存键 | Layer 缓存键改为 `hash(requirements.lock + runtime_version)`，升级 Python 自动失效旧缓存，不会误用 3.12 产物 |
| Z4 | 冒烟 | 部署后在别名上跑一次真实调用（读一次 `index.parquet`），确认 `fastparquet`/`numpy` 在 3.14 下可加载；写侧烟测用 **`deploy/smoke/{sha}.txt`**（CI 部署角色写、写后即删并断言 404），不写 `users/`、不带标签、不留孤儿（H4） |
| Z5 | 成本与性能 | 成本不变（$0.61/$1.38/$2.67）。**性能不预设**：3.14 的收益是更晚的弃用日（2029-06-30）与语言特性，**冷启动需实测回填**——AWS 官方提示新运行时发布初期因使用量少、缓存预热不足，冷启动可能更长，叠上 Parquet Layer 的 +80–150ms 更该实测；不启用实验性 free-threading / JIT（Lambda 托管运行时无 t-build） |

**已知限制**：`python3.14` 弃用日 2029-06-30（Amazon Linux 2023），比 3.12 的 2028-10-31 更晚，属于延长而非缩短生命周期；Layer 里的 `numpy`/`fastparquet` 必须有 3.14 的 manylinux wheel，若无 wheel 则在构建镜像内源码编译（Amazon Linux 2023 自带 gcc，需装 `gcc-c++`/`make`，构建时间约 +40 秒，仍是首次或 lockfile 变更时才付）。Node 24 于 2028-04 进入 EOL，届时升 26 只改 `.nvmrc` 与 CI 一行。

### 15.19 v1.13.1 修订：H1–H5 收口（v1.13 增量审核）

| ID | 级别 | 问题 | 整改 |
|---|---|---|---|
| H1 | P2·文档矛盾 | 第 3 章后端行残留「Python 3.12」，与 12.3/12.4/15.18 的 3.14 冲突；照旧文会建出 3.12 函数 + 3.14 镜像 Layer，运行期才炸 | 第 3 章改「**Python 3.14**」，全文运行时只剩一处口径 |
| H2 | P3·算术表述 | 规则句「0.30+0.60+1.20 = $1.98」字面相加为 2.10；「$6.38 → $6.4」是四舍五入显示，与截断规则不一致 | 改写为「各档中心值 + 各档日志」逐档相加（0.91/1.98/3.87），并注明**不是三档日志相加**；$6.38 不再缩写 |
| H3 | P3·措辞 | 「3.14 略快」与官方「新运行时初期冷启动可能更长」相悖 | Z5 改「性能不预设，冷启动实测回填」，保留弃用日更晚这一确定收益 |
| H4 | P3·运维细节 | 冒烟临时 key 无命名与清理约定，无标签则当前版本永不过期；写进 `users/` 会污染数据空间 | 固定 `deploy/smoke/{sha}.txt`，CI 部署角色写后即删并断言 404，重试前清同前缀残留（12.4 步骤 7、15.18 Z4） |
| H5 | P3·口径留痕 | GHA 漂移估算 100→60 分钟未记录，合计 1,040→1,000 | 12.8 GHA 行加注变更原因；本表留痕 |

**审核结论（原文摘录）**：Y1–Y10 十项 10/10 闭环；v1.12 三仓 public 与 GitHub 官方口径逐条吻合；v1.13 运行时主张（`python3.14`、`public.ecr.aws/lambda/python:3.14`、弃用日 2029-06-30、JIT/free-threading 禁用、Node 24 EOL 2028-04）与官方一致；成本三档复算零变动。修掉 H1 即可冻结，H2–H5 随本版并入后**进入实现阶段**。

### 15.20 v1.13.3 修订：K1–K4 收口（v1.13.2 增量审核）

| ID | 级别 | 问题 | 整改 |
|---|---|---|---|
| K1 | P2·权限缺口 | 12.5 的 `cloudjian-gha-backend-role` 对 `deploy/*` 只有 Put/Get，而 12.4 步骤 7 要求冒烟「写后即删」并断言 404 → 删除 AccessDenied、断言失败，每条 backend 流水线稳定标红（与 P0-2 同型的权限-功能错配） | 12.5 补 `s3:DeleteObject`（限 `deploy/*`），同时覆盖「重试前清同前缀残留」 |
| K2 | P2·端点归位 | 8.1 把换签授权写在 `POST /assets/presign`（上传端点），而 12.1 的换签路由是 `GET /assets/{asset_id}/url`；`GET` 无请求体，`note_id` 传入方式未定义 | 授权规则改落 `GET /assets/{asset_id}/url?note_id=…`，批量走新增的 `POST /assets/urls`；`presign` 只保留「定前缀 + 锁 Content-Type + 强制私有」职责；目录共享上下文由服务端按 `note_id` 反查 |
| K3 | P2·链路缺口 | 7.4 跨用户写路径清单漏 `_refs.json`；「共享目录内新建笔记 + 插入自己上传的图」时，owner 的 `_refs.json` 永远不含该 asset → 8.1 换签校验失败 → 裂图 | 拍板「**图片随笔记前缀**」：共享笔记里的插图落笔记所属者前缀（8.2），`_refs.json` 按笔记前缀归属（8.3），7.4 写路径清单扩为六处并写明插图者的越权边界 |
| K4 | P3·载体未定义 | T-10 要求写审计日志，但未定义落到哪、什么格式、保留多久 | 定稿：走既有 CloudWatch 日志组、单行 JSON（`share_id/action/actor/target/ts`）、保留 30 天，零新增存储与生命周期规则 |

> **核销边界**：本轮报告称送达文本止于 16.1、第 17–19 章未随消息传到。该问题属传输侧，不影响文档本身；本节之后即为完整 16–19 章，第 19 章的逐字核销可直接以本文件为准。

### 15.21 v1.13.4 修订：T-A…T-H 末梢定稿

| ID | 事项 | 定稿 | 落点 |
|---|---|---|---|
| T-A | 错误码表码值与 `params` 契约 | 整表随首个业务接口 PR **冻结**，之后只增不改；新增行缺 HTTP 状态或 `params` 契约即 CI 失败 | 9.4、19.3 |
| T-B | 草稿 256KB / 提前 10 分钟 | 保留为可调实现参数；底线是**不允许静默丢稿**，调整须同步 9.7 文案与 19.5 验收 | 10、19.3 |
| T-C | 「被引用数」口径 | 当前前缀 `_refs.json` 的 note 条数（同篇去重），公开/私有同口径，不含跨前缀与外链；UI 写「被 N 篇笔记引用」 | 8.4 |
| T-D | 共享笔记插图的空间归属提示 | 首次插图一行轻提示「图片存储计入笔记所有者」，每会话一次、不阻断 | 8.2 |
| T-E | 只读态版本入口 | 只渲染「对比」，「回滚」**不渲染**（不置灰），无二次确认弹窗 | 7.4 |
| T-F | 语言相关排序 | 规则 v1.13.2 已在 9.7（`Intl.Collator`）；本次在 9.6 补交叉引用，禁止两处口径 | 9.6、9.7 |
| T-G | 到期横幅措辞与多语言长度 | 单行不弹模态、只给「立即保存」、不给「续期」；弹性宽度不写死 pixel；三语文案给定 | 10 |
| T-H | 离线编辑 | 本期不做（**已产品确认**）；断网转只读 + 本地草稿 + API 明确失败，**不做乐观假保存**；真离线条单独立项 | 10 |

## 16. 已知取舍与缺陷状态

### 16.1 设计取舍（有意为之）

| 项 | 取舍 | 代价 | 应对 |
|---|---|---|---|
| 单数据桶 | 省配额、省运维 | 依赖权限配置精确性 | 11.1 三道闸 + CI 穿透测试；必要时可拆公开桶 |
| Parquet 索引 | 技术选型偏好 + 离线分析（已决策保留） | 不可读、Layer、冷启动 | 5.3.6 运维工具；后端工程负责 Layer 发布；15.3 记录代价 |
| 无实时协同 | 保持纯 S3 + Lambda | 同时编辑需手动合并 | 行级 diff 面板，协作以错峰为主 |
| 20 小时双 Token | 免去刷新链路 | 撤销靠服务端校验兜底；AccessToken 有效期需显式配置 | 4.6 注册表 60 秒缓存 + `auth_time` 比对 |
| Slug 文件名 | 可读、路径直观 | 重名需加后缀、标题改动要搬文件 | `note_id` 承担身份，slug 不承担唯一性 |
| 非实时搜索 | 无外部检索引擎 | 大库变慢 | 14.2 阶段三可换 OpenSearch |
| 仅 PC 端 | 省移动端适配 | 手机不可用 | 明确不在范围内 |
| 不建 VPC | 零网络成本、零网络运维面 | Lambda 出网走公网，无安全组级隔离 | 12.6 决策依据；边界靠 IAM 最小权限 + 桶策略前缀化 + 关停 S3 公共访问 |
| 三仓分离 | 流水线解耦、权限最小 | 跨仓契约靠 SSM，需按序首次部署 | 12.2 参数总线与部署顺序 |
| 共享收件箱集中索引 | 读取从全库 LIST 降为 1 次 GET | 多写者热对象，需幂等 + 每日对账 | 7.2 条件写重试与 `rebuild_index.py` 对账 |
| 三仓 public + 单环境 | 免费分支保护、免费 Actions；拓扑最简单 | **架构与资源标识全部公开**，攻击面可见；无预发缓冲 | 12.4 原生分支保护 + 部署门禁；secret scanning；匿名穿透 CI 断言；破坏性变更先在 dev 造数验证 |
| 公开图随笔记进 `assets/_trash/` | 清理意图保留且恢复链完整 | 30 天内图片仍占存储（约 3% 增量） | 8.3 + 12.7 标签生命周期 |

### 16.2 已识别缺陷（整改后状态）

| ID | 状态 |
|---|---|
| R1–R4 | 已整改，纳入上线前验收 |
| R5–R8、R10 | 已整改，纳入 v1.1 功能定稿验收 |
| R9 | 表述修正 + 运维工具已补；已决策保留 Parquet（15.3） |
| R11–R15 | 已整改（文档层） |
| R16 | 已整改（成本与升级章节重写，v1.6 按复审口径复核） |
| N1 · 私有图链路阻断 | 已整改（改 S3 预签名 URL） |
| N2 · OIDC 权限缺口 | 已整改（12.5 补齐 4 项权限） |
| N4 · 非当前版本未清理 | 已整改（12.7 生命周期三规则） |
| N5 · 共享列表全库 LIST | 已整改（7.2 收件箱索引） |
| W1–W8（v1.9.3 收口） | 6 项闭环、2 项部分闭环 → v1.10.1 补 X6/X13 后全部闭环 |
| X1 · OIDC `sub` 与 Environment 互斥 | 已整改（12.5 用 `environment:dev`；结论在 v1.11 单环境下继续有效） |
| X2 · IAM 跨环境越权 | **已随 v1.11 单环境消解**；等价风险转为「合入 dev 即改线上」，由**部署门禁**控制（12.4；Free 私有仓无原生分支保护，Y2） |
| X3 · CI 分钟数未入成本 | 已整改（12.8 GHA 行重算；单环境后 ≈1,040 分钟/月 → $0） |
| X4 · 公开图引用判定跨用户不可判 | 已整改（8.3 改为移入 `assets/_trash/` + 30 天，恢复链完整） |
| X5 · 强制私有拦在 register | 已整改（8.2 前置到 presign；配置定在 `_team_config.json`） |
| X6–X18 | 已整改（v1.10.1，落点见 15.14） |
| N9 · 新引入 11 处矛盾 | 已整改（15.5 逐条列明） |
| P0-1 · 生命周期前缀通配符失效 | 已整改（12.7 标签过滤 + 命中测试验收） |
| P0-2 · 执行角色缺 Cognito 管理动作 | 已整改（12.3 补 6 个动作） |
| P0-3 · SPA 路由与白名单冲突 | 已整改（11.1 catch-all rewrite，不用错误页映射） |
| P1-4 · 数据桶无 CORS | 已整改（8.2 / 12.1） |
| P1-5 · 改密会话失效 | 已整改（`password_changed_at` + `auth_time`，含秒/毫秒换算） |
| P1-6 · 定时任务无归属 | 已整改（12.3 第 6 个函数 + Scheduler） |
| P1-7 · SSM 写权限过宽 | 已整改（12.5 收窄） |
| P2-1/P2-2/P2-3 | 已整改（6.3 / 6.1+12.3 / 12.7） |
| P3 · 6 处文档残留 | 已整改（15.6 逐条列明） |
| F1 · 12.7 残留旧规则块 | 已整改（删除残留，仅留标签化三规则 + 空 filter 规则） |
| F2 · SPA 回退与 403 断言互斥 | 已整改（catch-all rewrite，撤销错误页映射） |
| F3 · CopyObject 漏打标签 | 已整改（`copy_with_retention` + CI 拦 `copy_object`/`upload_file`） |
| F4 · scheduler 权限与执行角色缺失 | 已整改（terraform-role 补动作 + `cloudjian-scheduler-role`） |
| F5–F12 | 已整改（详见 15.7） |
| 网关计价（v1.8/v1.9.1） | 已执行：REST → HTTP API；日志行归零与 C 档 26.4 万修正后，三档 **$0.61 / $1.38 / $2.67**（15.8/15.11） |
| 网关鉴权 | 已执行：JWT 授权器前置 + `token_use` 硬门槛 + API 侧 CORS（15.9） |
| G1–G4（P1） | 已整改（15.10） |
| V1–V10 | 已整改（15.11） |
| W1–W8 | 已整改（15.12） |
| G5–G16（P2/P3） | 已整改（15.10 逐条列明） |
| H1–H5 | 已整改（15.19） |
| K1 · backend 发布角色缺 DeleteObject | 已整改（12.5 补 `s3:DeleteObject`，限 `deploy/*`） |
| K2 · 换签授权挂错端点 | 已整改（8.1 归位到 `GET /assets/{asset_id}/url?note_id=…`，新增 `POST /assets/urls`） |
| K3 · 共享插图引用计数缺失 | 已整改（图片随笔记前缀，`_refs.json` 按笔记前缀归属，7.4 写路径扩为六处） |
| K4 · 审计日志载体未定义 | 已整改（7.3 定稿：CloudWatch 结构化日志，30 天） |
| T-A–T-H（末梢 8 项） | 已定稿（15.21 / 19.7）；T-H「断网不可编辑」已于 2026-11-26 经产品确认 |

---

## 17. 已确认事项（v1.13.1 封版）

7 项原「待确认」已全部拍板，结论落进对应章节；连同 v1.10.1 的 X1–X18 与 v1.11.1 的 Y1–Y10 整改，**在 v1.13.1 时点无开口项**（跨环境残余面已随单环境消解，12.6 不再有该段）。v1.13.2 新增的 13 项 TODO 逐条核实结论见**第 19 章**，其中 1 项关闭、5 项修正表述后成立、另有 1 项 P1 缺口补入 8.1。v1.13.6 追加 **17.11 回收站彻底删除**：

| # | 事项 | 结论 | 落点 |
|---|---|---|---|
| 17.1 | 共享目录的展示形态 | **一条虚拟目录**（「共享给我 / 目录名」），点进去展开真实子结构；单篇共享显示为独立笔记 | 7.3 |
| 17.2 | 回收站是否打平展示 | **还原原目录树**，支持目录级一键恢复；恢复为异步 job，树结构缓存 15 分钟，重名追加 `-1` | 6.5 |
| 17.3 | 整目录导出 ZIP | **支持**，保留目录结构；超 200 篇或 20MB 转异步 job | 6.6 |
| 17.4 | 删除笔记时清理公开图 | **联动清理**：仅被该笔记引用的公开图（及私有孤儿）移入 `assets/_trash/` 并打 30 天标签，随回收站一起物理清理；恢复笔记时图片一并恢复 | 8.3 |
| 17.5 | 可见性相关的管理员开关（v1.13.7 改造） | **需要，但已下沉到笔记级**：`default_note_visibility`（新建笔记默认档位）+ `force_private`（禁止把笔记设为公开）；拦截位置从 presign 改到「设置笔记可见性」接口，配置仍存 `users/_team_config.json`（5 分钟缓存）。图片不再有独立可见性 | 8.1 / 8.2 / 12.1 |
| 17.6 | 第四种语言 / 语言级内容规范 | **都不需要**：`zh-CN` / `en-US` / `ja-JP` 封版；`lang` 缺失或 `unknown` 时启发式推断，仅用于检索、不做校验 | 9.1 |
| 17.7 | 三仓发布模型 | **只保留 dev 一个环境**：`feat/xxx → dev（合并即上线）→ main（只归档不部署）`；三仓各一条 OIDC 角色（`environment:dev`），无 staging/prod | 12.4 / 12.5 / 13.2 |
| 17.12 | 图片可见性是否独立于笔记（v1.13.7） | **不独立**：图片完全跟随笔记，笔记 `private` 则图仅对可读者可见、笔记 `public` 则图匿名可读；一张图被多篇引用时取「最宽」档（公开优先）。单图可见性、`ASSET_VISIBILITY_FORCED`、presign 侧 `visibility` 参数全部删除 | 8.1 / 8.2 / 8.4 |
| 17.11 | 回收站是否支持主动彻底删除/清空（v1.13.6） | **支持四型**：单篇 / 批量 ≤200 篇（仅笔记）/ 整目录子树 / 清空。一律异步 job，以索引 `purge_state=pending` 为状态机、先进后删、最后条件提交；`notes` 需 `ack=true`、`all` 需 `confirm="EMPTY_ALL"`。仅 owner 本人可操作，后台不提供代删；多选只在回收站视图 | 6.5 / 8.3 / 12.1 |

### 17.8–17.10 实现约束（v1.7 追加，随 P0-1 标签方案落地）

8. **统一写入/拷贝封装**：需要 TTL 的对象一律走 `put_with_retention(key, body, retention)` 或 `copy_with_retention(src, dst, retention)`（后者必须 `TaggingDirective=REPLACE`）；目录搬移用不加标签的独立封装；散落的裸 `put_object` / `copy_object` 视为缺陷
9. **CI 静态检查**：后端仓加一条 grep 门禁 —— 除 `storage/retention.py` 与目录搬移封装的白名单外，出现 `put_object(` / `copy_object(` / `upload_file(` / `upload_fileobj(` 即失败；这条比代码评审更可靠，因为漏打标签的症状是「30 天后才发现没回收」，线上完全无感
10. **标签键值收敛**：键固定 `cj:retention`，值只允许 `30d` / `1d` 两个，新增保留档位需同步改 12.7 的两条生命周期规则，不允许出现第三种值而无对应规则

---

## 18. 术语与缩写

| 术语 | 含义 |
|---|---|
| OAC | Origin Access Control，CloudFront 访问 S3 的授权机制 |
| ETag | S3 对象的实体标签，条件写（`If-Match`）的比对依据 |
| If-Match | S3 条件写请求头，不匹配返回 412 |
| TOCTOU | Time-of-check to time-of-use，先检查后使用之间的竞态窗口 |
| ABA | 值被改走又改回，导致基于内容比对的乐观锁失效 |
| note_id | ULID 形式的笔记全局唯一身份，与文件名解耦 |
| Slug | 由标题转换出的 URL 安全文件标识，仅作可读文件名 |
| ULID | 可排序的 26 位唯一标识，优于 UUID 的时间局部性 |
| MAU | 月活跃用户数 |
| i18n | internationalization，国际化 |
| locale | 语言与区域的组合标识，如 `zh-CN`、`ja-JP` |
| CloudFront Function | 分发边缘执行的轻量 JS 函数，用于路径白名单等逻辑 |
| 乐观锁 | 写入时校验版本，不一致则拒绝并重试的并发控制方式 |

---

## 19. 待办确认与决议（v1.13.2 → v1.13.4）

> 本节对应《TODO（缺失、矛盾、需产品确认）》T-01…T-13。核实方式：逐条回原文对照，区分「真缺失」「表述有误但结论可定」「已有定案」。结论分布：**7 项成立、5 项修正表述后成立、1 项关闭**；另补 3 项表外缺口，其中 1 项为 P1。

### 19.1 逐条决议

| ID | 原判断核实 | 决议 | 落点 |
|---|---|---|---|
| T-01 | 成立（9.4 仅机制 + 1 示例；13.3 只定命名格式） | 全部非 2xx 统一 `{code, params, data?}`；412 由「裸返四份数据」改为 `NOTE_CONFLICT` + `data`；`error_codes.py` 为唯一真源，实现前产出全表 | 9.4、7.5、5.3.5、6.1 |
| T-02 | 成立（6.4 有回滚，7.4 未提版本） | `read` 可看历史与对比、**不可回滚**；`edit` 可回滚。另补「edit 保存写 owner 的 `versions/{note_id}/` 与索引」为唯一跨用户写路径，须显式校验 share 记录 | 7.4、6.4 |
| T-03 | 成立（2.2 仅四字，无规则） | 只做自由标签：≤20 个/篇、单个 ≤24 字符，不做层级/颜色/重命名/管理页；`Frontmatter.tags` 为真源，`index.tags` 为派生 | 2.2、5.3.2 |
| T-04 | 部分成立，前提写错 | 30 天按对象 `LastModified` 计，进 trash 是 CopyObject 新建对象、起点≈**删除时刻**，非原笔记写入时间；文案统一「约 N 天后清理」，N 由 `LastModified` 现算 | 6.5 |
| T-05 | **已有定案，关闭** | 维持 PUT + 登记校验（8.2 的路线②），不改预签名 POST；10MB 走前端前置校验 + `HeadObject` 二次校验；文案不称「服务端强制」 | 8.2 |
| T-06 | 部分成立（矩阵只描述两格） | 「强制私有」一律 **400 明确拒绝**，不做静默改写；补齐四格行为矩阵，明确强制私有优先级高于默认可见性 | 8.1 |
| T-07 | 成立 | 成员列表 + 前缀搜索读 `_registry.parquet`（复用 60s 缓存）；**不显示在线状态**；仅允许 `status=active` 且非本人 | 7.2 |
| T-08 | 成立（只写「列表只读」） | 搬移期间整棵子树禁写（新建/编辑/删除/移动/共享变更/导出），统一 `409 JOB_RUNNING`；前端按 job 状态禁按钮 | 6.1 |
| T-09 | 成立，**升级为 P1** | exp 前 10 分钟常驻提示；输入 debounce 5s 写 localStorage 草稿；重登后按 `base_version` 决定「直接回填」或「走 7.5 差异面板」 | 10 |
| T-10 | 成立 | 保存返回 **`403 SHARE_REVOKED`（不是 412）** + 保留内容 + 「另存为我的笔记」；15 分钟缓存收敛记为已知取舍 | 7.3、7.4 |
| T-11 | 部分成立（5.1 已列三项） | `profile.json` 锁 6 项：`ui_lang`/`tz`/`theme`/`editor_mode`/`list_sort`/`page_size`；目录展开态、面板宽度等走 localStorage | 5.1、10 |
| T-12 | 大部分已有（9.2 已定三段式） | 补派生规则 `errors.code.<code 小写蛇形>` 与 CI 双向校验（码表 ↔ 语言包各查一次） | 9.4、9.7 |
| T-13 | 部分不成立（摘要长度已定） | 保留「前后各 60 字 + 512KB」不变；补 `origin`/`owner_name` 字段，共享结果路径只给相对共享根一段 | 6.3 |

### 19.2 表外缺口（本次补入）

| # | 缺口 | 影响 | 决议 | 落点 |
|---|---|---|---|---|
| ① | 共享笔记中的私有图如何换预签名，全文未定义 | **P1**：共享笔记大面积裂图 | 按笔记可见性授权（`read`/`edit` 均可签），且 `asset_id` 必须在该 note 的 `_refs.json` 引用列表内；公开图无需授权 | 8.1 |
| ② | 412/409 是「错误」还是「数据」，9.4 与 5.3.5/7.5 口径冲突 | 前端拦截器要写两套分支，极易漏判 | 并入 T-01 的统一信封，412 用 `data` 承载四份数据 | 9.4、7.5 |
| ③ | 目录搬移未刷新 `shares/*.json` 的 `target_dir`（6.1 缺，6.5 有） | 已共享目录搬移后指向不存在路径 | 6.1 补第 5 步：任务收尾同步改写 `target_dir` 与 `_share_inbox.parquet` | 6.1 |

### 19.3 实现期仍需产出（不阻塞封版）

1. `error_codes.py` 全表内容（本节只定结构、命名与生成方式；码值、`params` 契约在首个业务接口开发前一次性产出，之后只增不改）
2. 草稿大小上限（256KB）与到期提示时长（10 分钟）属实现参数，允许微调；但**不允许退化成「到期静默丢稿」**
3. 共享图片换签复用 8.1 既有的批量签发接口，不新增接口、不新增 `_refs.json` 之外的数据表

### 19.4 未改动的已知取舍

15 分钟权限/收件箱缓存收敛、5 分钟预签名 TTL、20 小时硬到期、30 天回收站：均为既有取舍，本节不引入新机制去消除，只要求 UI 与文案把「约」「最长 N 分钟」这类限定词写准。

### 19.5 验收补充（三条即可覆盖本次改动）

1. 未登录/降权语义：`401` 跳登录、`403 SHARE_REVOKED` 转存、`403 SHARE_FORBIDDEN` 提示，三条互不串台
2. 412 响应体符合统一信封（`code` + `data.diff`），且前端只走冲突面板一条分支
3. 越权换签：以 `read` 身份请求共享笔记中**未被该 note 引用**的 `asset_id`，必须 403；引用列表内的必须 200

### 19.6 K1–K4 收口（v1.13.3）

v1.13.2 的专项审核新增 4 项（P2×3、P3×1），全部属「新决策与既有契约的接缝」，不动架构与成本。收口后本节 19.1 的结论仍然成立，只是两处落地形态变了：

| 项 | 原形态（v1.13.2） | 收口后（v1.13.3） |
|---|---|---|
| 换签端点 | 挂在上传端点 `POST /assets/presign` | 归位到 `GET /assets/{asset_id}/url?note_id=…`；批量 `POST /assets/urls` |
| 共享笔记插图 | 图落插图者前缀，owner 的 `_refs.json` 查不到 | **图落笔记所属者前缀**，`_refs.json` 同前缀，链路单前缀闭合 |
| 跨用户写路径 | 3 处（正文、versions、索引/分片） | 6 处（增 `_refs.json`、`assets/public\|private` 新增上传） |
| 审计日志 | 只写「写一条审计日志」 | CloudWatch 结构化 JSON，30 天，复用既有日志组 |
| backend 发布角色 | `deploy/*` 仅 Put/Get | 增 `s3:DeleteObject`（限 `deploy/*`） |

**用一句话说清 K3 的取舍**：图跟笔记走，不跟人走。换来的是「引用计数、换签、删除迁图、恢复迁回」全在单前缀内闭合、零新表零跨用户查表；付出的是插图存储计在笔记所属者头上，且插图者自己的图库看不到这张图。若日后认为配额归属不合理，改动点只在 8.2 的 presign 定前缀规则，链路其余部分不受影响。

**实现期新增断言（并入第 19.5 的验收）**：

1. 共享笔记私有图换签：`GET /assets/{id}/url?note_id=…` 在「权限不足」「asset 不在 refs」「note 与 asset 前缀不一致」三种情况下分别返回 403，正常情况返回 200 且 URL 5 分钟有效
2. 共享目录内插图：以 `edit` 身份在 owner 目录新建笔记并上传，图必须落 **owner 前缀**；随后 owner 打开该笔记能正常渲染（私有与公开各一次）
3. backend 冒烟：`deploy/smoke/{sha}.txt` 写 → 删 → `head-object` 404，三步均须 200/404，不得出现 AccessDenied

### 19.7 末梢定稿（v1.13.4，T-A…T-H）

本节 19.1 的 13 项已全部闭环，本表只记「仍会影响产品表现」的 8 项末梢，处理原则是：能用一句话定死的直接定，不定死就会在实现期各写各的。

| ID | 结论 | 一句话理由 |
|---|---|---|
| T-A | 码表随首个接口 PR 冻结 | 码值一旦上线就不能改语义，晚定不如早冻结；冻结前允许迭代 |
| T-B | 参数可调、底线不可退 | 256KB/10 分钟是体验参数；「到期静默丢稿」是信任问题，不是参数问题 |
| T-C | 只报「本前缀内被 N 篇引用」 | 跨前缀与外链没有数据源，报大了等于撒谎 |
| T-D | 首次插图给一行轻提示 | 归配额这件事必须让用户知情，但不值得为它加确认弹窗 |
| T-E | 只给按钮，不给置灰 | 置灰诱导点击后失败，比不显示更容易被当成 bug |
| T-F | 单一实现口径 | 同一排序规则两处写法，必然在某个语言上分叉 |
| T-G | 交代文案与宽度约束 | 英日文案长 40%，不约束就会在按钮旁溢出 |
| T-H | 不做离线、不做假保存 | 做一半的离线比不做更危险；失败要失败得诚实 |

**T-H 已确认（2026-11-26，产品侧 owner 明确接受）**：「断网即不可编辑」是本期取舍，不再是开口项。若日后业务侧改口，需单独立项（本地 CRDT + 重连合并 + 冲突策略），并重新评估 T-09 的草稿机制与 7.5 的冲突面板是否够用；**不建议在原方案上打补丁式加离线**。至此 19.1 的 13 项与 19.7 的 8 项全部闭环，无待确认项。
