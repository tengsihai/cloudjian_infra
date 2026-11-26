# 云笺 CloudJian — 共同接口契约 v0.1

> **新人入口**：[docs/README.md](README.md)。本文是字段/路由/错误码**唯一真源**。

> 读者：T1 基础设施 / T2 后端 / T3 前端 / T4 质量。**四个团队只以本文对齐字段、路由、错误码；本文与代码不一致视为缺陷。**

> **修订史**：文首变更说明已移至 [云笺-修订史归档.md](云笺-修订史归档.md)。


## 1. 通用约定

| 项 | 约定 |
|-|-|
| 基址 | `https://<api-id>.execute-api.ap-northeast-1.amazonaws.com`，Stage `dev`，由 SSM `/cloudjian/api-url` 注入 |
| 认证 | 业务路由带 `Authorization: Bearer <AccessToken>`（Cognito **AccessToken**，不是 ID Token）；**唯 `GET /public/notes/{token}` 不鉴权** |
| 错误信封 | 非 2xx：`{"code","params","data"?}`；`data` 只用于需结构化上下文（412/409/403 转存） |
| 成功体 | 直接返回资源或 `{items,page,page_size,has_more}`，不再包 `data` |
| 语言 | 后端不返回自然语言；`code → errors.code.<小写蛇形>` |
| 时间 | 接口一律 UTC 毫秒 int64；Frontmatter 落盘 ISO8601+偏移 |
| 分页 | `page`（1 起）+ `page_size`（默认 20，可选 20/50/100，上限 100）；列表默认 `updated_at` 倒序 |
| ETag 读 | `GET /notes/{id}` 响应头 `ETag`，body 同时给 `version` |
| ETag 写 | 请求头 `If-Match`，透传 S3；响应回新 `ETag`；**不放进 body** |
| 条件写失败 | 412 `NOTE_CONFLICT` / 409 `DELETE_CONFLICT` / 404 `NOTE_NOT_FOUND`；索引内部重试 3 次 |
| 响应上限 | 搜索 ≤512KB；同步 ≤6MB；网关负载 10MB |
| CORS | 网关统一配（AllowOrigins=CDN、Methods 含 PATCH/DELETE、AllowHeaders 含 `if-match`、Expose `etag`、MaxAge 600）；**Lambda 不输出 CORS 头** |
| 幂等 | `POST /assets/register` 按 `asset_id`；共享收件箱条件写 + 退避；job 按 `cursor` 续跑；purge 靠 `purged[]` |
| 标题 | `title` 可空，落库「未命名笔记」（按 `ui_lang`），不返回 `NOTE_TITLE_REQUIRED` |

## 2. 路由总表

> 「鉴权」列：JWT＝需 AccessToken；**匿名＝无需任何凭证**。

### 2.1 笔记（notes-api）

| # | 方法 | 路径 | 鉴权 | 关键入参 | 出参 |
|-|-|-|-|-|-|
| N1 | GET | `/notes` | JWT | `category_path?`、`tag?`、`sort`、`page`、`page_size` | `{items:[{note_id,title,slug,category_path,tags,updated_at,version,own_share,visibility}],...}` |
| N2 | POST | `/notes` | JWT | `{title?,category_path,content?,tags?,lang?}` | 201 `{note_id,slug,category_path,version:1}` + ETag |
| N3 | GET | `/notes/{note_id}` | JWT | `include=content\|meta` | `{note_id,title,slug,category_path,tags,lang,visibility,created_at,updated_at,version,content}` + ETag |
| N4 | PUT | `/notes/{note_id}` | JWT | Header `If-Match` 必填；`{content,title?,tags?,lang?,base_version}` | 200 `{note_id,version,updated_at}` + ETag |
| N5 | DELETE | `/notes/{note_id}` | JWT | `If-Match`（建议） | 200 `{note_id,trashed:true,deleted_at}` |
| N6 | POST | `/trash/purge` | JWT | `{scope:note\|notes\|dir\|all, note_ids?, category_path?, ack?, confirm?}` | 202 `{job_id,accepted,rejected[]}` |
| **N7** | POST | `/notes/{note_id}/visibility` | JWT（仅 owner） | `{visibility:"private"\|"public"}` | 202 `{job_id,visibility}` |
| **N8** | GET | `/public/notes/{public_token}` | **匿名** | — | 200 `{title,content,updated_at,images:[{asset_id,url}]}` |

### 2.2 版本 / 搜索 / 目录（notes-api）

| # | 方法 | 路径 | 关键入参 | 出参 |
|-|-|-|-|-|
| V1 | GET | `/notes/{note_id}/versions` | `page`、`page_size` | `{items:[{ts,size,created_at}],...}` |
| V2 | POST | `/notes/{note_id}/versions/{ts}/restore` | `{base_version}` | 200 `{note_id,version,restored_from}` + ETag |
| V3 | GET | `/notes/{note_id}/versions/{ts}` | — | `{ts,content}` |
| S1 | GET | `/search` | `q` 必填、`page`、`page_size`≤20 | `{items:[{note_id,title,category_path,snippet,origin,owner_name?,updated_at}],has_more,total_hint?}` |
| S2 | GET | `/dirs` | `path?`、`depth?`、`scope=mine\|shared` | `{items:[{path,name,type,note_id?,updated_at,has_children}]}` |
| S3 | POST | `/dirs/move` | `{source_path,target_path,mode=move\|rename}` | 202 `{job_id}` |
| S4 | POST | `/dirs` | `{path,name}` | 201 `{path}` |
| S5 | PATCH | `/dirs` | `{path,description?,shared_with?}` | 200 `.dir_meta` |
| S6 | DELETE | `/dirs` | `{path}` | 202 `{job_id}` |

### 2.3 共享（share-api）

| # | 方法 | 路径 | 入参 | 出参 |
|-|-|-|-|-|
| H1 | GET | `/shares` | `scope=outgoing\|incoming`、`page` | `{items:[{share_id,owner_uuid?,owner_name?,target_type,target_note_id?,target_dir,level,created_at}],...}` |
| H2 | POST | `/shares` | `{target_type,target_note_id?\|target_dir?,grantee,level}` | 201 `{share_id}` |
| H3 | DELETE | `/shares/{share_id}` | — | 204 |

### 2.4 图床（asset-api）

| # | 方法 | 路径 | 入参 | 出参 |
|-|-|-|-|-|
| A1 | POST | `/assets/presign` | `{note_id,filename,content_type,size}`（**无 visibility**） | `{upload_url,method:"PUT",headers,key,asset_id,expires_in,asset_visibility}` |
| A2 | POST | `/assets/register` | `{note_id,asset_id,key,etag,size,content_type}` | 201 `{asset_id,url,visibility}`；公开→CDN，私有→`asset://{asset_id}` |
| A3 | GET | `/assets/{asset_id}/url` | `note_id` 必填 | `{url,expires_at}`（TTL 300s） |
| A4 | POST | `/assets/urls` | `{note_id,asset_ids[]}` ≤50 | `{items:[{asset_id,url,expires_at}],failed:[{asset_id,code}]}` |
| A5 | GET | `/assets` | `note_id?`、`page` | `{items:[{asset_id,filename,size,created_at,visibility,ref_count,public_ref_count,url?}],page}` |

### 2.5 后台 / 导出 / 任务 / Profile

| # | 方法 | 路径 | 入参 | 出参 |
|-|-|-|-|-|
| M1 | GET | `/admin/users` | `page`、`q?`、`status?` | `{items:[{user_uuid,username,role,status,created_at,last_login_at}],page}` |
| M2 | POST | `/admin/users` | `{username,initial_password,email?,role}` | 201 `{user_uuid,status:"FORCE_CHANGE_PASSWORD"}` |
| M3 | PATCH | `/admin/users/{sub}` | `{status?,role?}` | 200 `{user_uuid,status,role}` |
| M4 | DELETE | `/admin/users/{sub}` | **不挂载**（路由不存在） | — |
| M5 | POST | `/admin/users/{sub}/reset` | `{new_password?}` | 200 `{user_uuid,password_changed_at}` |
| M6 | GET | `/admin/team-config` | — | `{default_note_visibility,force_private,version}` + ETag |
| M7 | PUT | `/admin/team-config` | `{default_note_visibility,force_private}` + `If-Match` 可选 | 200 `{...}` + ETag |
| E1 | POST | `/exports` | `{note_id}` / `{category_path,recursive}` | 同步 200 `{download_url,expires_at}`；异步 202 `{job_id}` |
| E2 | GET | `/exports/{job_id}` | — | `{job_id,status,progress,total,download_url?,error?}` |
| J1 | GET | `/jobs/{job_id}` | — | `{job_id,type,status,progress,total,cursor,error?,result?}` |
| P1 | GET | `/profile` | — | `{ui_lang,tz,theme,editor_mode,list_sort,page_size}` + ETag |
| P2 | PUT | `/profile` | 6 项子集（`page_size`∈{20,50,100}） | 200 + ETag |

### 2.6 路由 → 函数

| 函数 | 路由组 |
|-|-|
| `cloudjian-notes-api` | 2.1 全部（含 N8 匿名子路由）+ 2.2 全部 + J1 |
| `cloudjian-share-api` | 2.3 |
| `cloudjian-asset-api` | 2.4 |
| `cloudjian-admin-api` | M1–M7、P1/P2（或独立 profile） |
| `cloudjian-export-api` | E1/E2 |

> N8 必须**单独注册为无鉴权路由**（not 挂 JWT authorizer），且不得与 `/notes/{note_id}` 混在同一路径模板下。

## 3. 错误码（按域）

| 域 | 码 |
|-|-|
| 认证 | `AUTH_UNAUTHORIZED`(401)、`AUTH_TOKEN_EXPIRED`(401)、`AUTH_TOKEN_TYPE_INVALID`(401)、`AUTH_SESSION_REVOKED`(401)、`AUTH_FORBIDDEN`(403)、`ACCOUNT_DISABLED`(403) |
| 笔记 | `NOTE_NOT_FOUND`(404)、`NOTE_CONFLICT`(412)、`DELETE_CONFLICT`(409)、`NOTE_FORBIDDEN`(403)、`NOTE_IF_MATCH_REQUIRED`(400)、`NOTE_TAG_LIMIT`/`NOTE_TAG_TOO_LONG`(400)、`NOTE_TOO_LARGE`(413)、`NOTE_PATH_INVALID`(400)、`NOTE_QUERY_INVALID`(400) |
| 可见性 | **`NOTE_VISIBILITY_FORBIDDEN`(400)**、**`PUBLIC_NOTE_NOT_FOUND`(404)**、`PUBLIC_RATE_LIMITED`(429)、`JOB_RUNNING`(409) |
| 目录 | `DIR_NOT_FOUND`(404)、`DIR_PATH_INVALID`(400)、`DIR_MOVE_INTO_SELF`(400)、`DIR_MOVE_FAILED`(500/409)、`DIR_EXISTS`(409)、`DIR_FORBIDDEN`(403) |
| 共享 | `SHARE_FORBIDDEN`(403)、`SHARE_REVOKED`(403)、`SHARE_NOT_FOUND`(404)、`SHARE_INBOX_CONFLICT`(500)、`USER_NOT_FOUND`(400)、`USER_DISABLED`(400) |
| 图床 | `ASSET_TOO_LARGE`(400)、`ASSET_FORBIDDEN`(403，params.reason=`perm\|not_referenced\|prefix_mismatch`)、`ASSET_NOT_FOUND`(404)、`ASSET_BATCH_TOO_LARGE`(400)、`ASSET_NOTE_FORBIDDEN`(403)、`ASSET_TYPE_UNSUPPORTED`(400)、`ASSET_NOT_UPLOADED`(400)、`ASSET_KEY_MISMATCH`(400)、`ASSET_NOTE_REQUIRED`(400) |
| 回收站 | `TRASH_PURGE_SCOPE_INVALID`、`TRASH_BATCH_EMPTY`、`TRASH_BATCH_TOO_LARGE`、`TRASH_FORBIDDEN`、`TRASH_ITEM_NOT_FOUND`、`TRASH_PURGE_FAILED` |
| 后台 | `USER_EXISTS`(409)、`USER_INVALID`(400)、`PASSWORD_POLICY`(400)、`TEAM_CONFIG_NOT_FOUND`(404)、`TEAM_CONFIG_CONFLICT`(409)、`COGNITO_ERROR`(500)、`USER_LAST_ADMIN`(409) |
| 导出/任务 | `EXPORT_SCOPE_INVALID`、`EXPORT_SCOPE_AMBIGUOUS`、`EXPORT_FORBIDDEN`(403)、`EXPORT_JOB_FAILED`(500)、`EXPORT_NOT_FOUND`(404)、`EXPORT_EXPIRED`(410)、`JOB_NOT_FOUND`(404)、`JOB_FORBIDDEN`(403)、`JOB_EXPIRED`(410) |
| 通用 | `INTERNAL_ERROR`(500)、`QUOTA_EXCEEDED`(429/400) |

> 已删除：`ASSET_VISIBILITY_FORCED`（图片无独立可见性，改用 `NOTE_VISIBILITY_FORBIDDEN`）。`NETWORK_OFFLINE` 为前端本地态，不入后端码表。

## 4. 数据契约

### 4.1 笔记 Frontmatter（真源）

| 字段 | 类型 | 约束 |
|-|-|-|
| `note_id` | string | ULID 26 位 |
| `title` | string | 非空，≤200 |
| `slug` | string | 同目录重名 `-1/-2` |
| `category` | string | 多级路径 |
| `tags` | list | ≤20 个，单个 ≤24 |
| `lang` | string | `zh-CN/en-US/ja-JP/unknown` |
| **`visibility`** | string | `private`（默认）/`public` |
| **`public_token`** | string? | 仅 public 时存在，随机 22 位 |
| `created_at`/`updated_at` | ISO8601 | 索引存毫秒 |
| `version` | int | 单调递增 |

Frontmatter 不记录任何共享信息。

### 4.2 `index.parquet`（派生）

`note_id`、`title`、`slug`、`category_path`、`tags`、`lang`、**`visibility`**、`created_at`、`updated_at`、`version`、`is_deleted`、`deleted_at`、`purge_state`、`own_share`、`file_size`

### 4.3 `jobs/{job_id}.json`

`job_id`、`type`（`move_dir/restore_dir/trash_dir/purge_note/purge_notes/purge_dir/purge_all/visibility_migrate/export/reconcile/rebuild_index`）、`status`（`running/done/failed/partial`）、`root`、`target`、`cursor`、`total`、`done`、`moved/restored/migrated[]`、`purged[]`、`rejected[]`、`freed_bytes`、`visibility`、`error{code,failed_keys[]}`、`created_at/updated_at`

### 4.4 `assets/_refs.json`

`{note_id → [asset_id...]}` 与本笔记前缀内 `asset_id → {filename,size,created_at,refs:[note_id...]}`；`ref_count` 为引用篇数（同篇去重），`public_ref_count` 为其中 `visibility=public` 的篇数。

### 4.5 其他对象

| 对象 | 内容 |
|-|-|
| `shares/{share_id}.json` | `share_id`、`target_type`、`target_note_id?`、`target_dir`、`grantee`、`level`、`created_at` |
| `_share_inbox.parquet` | 读侧唯一入口，按 `grantee` 索引 |
| `_team_config.json` | `default_note_visibility`、`force_private`、`version`；5 分钟缓存 + If-None-Match |
| `public_tokens/{token}.json` | `{note_id, created_at}`；切回私有即删 |
| `profile.json` | `ui_lang`、`tz`、`theme`、`editor_mode`、`list_sort`、`page_size` |
| `.dir_meta.json` | `description`、`shared_with`、`created_at` |

### 4.6 存储前缀与可见性

| 场景 | 前缀 | 访问 |
|-|-|-|
| 笔记 public | `assets/public/{note_id}/{asset_id}/{file}` | CDN 匿名 |
| 笔记 private | `assets/private/{note_id}/{asset_id}/{file}` | 预签名 300s，不经 CDN |
| 统一规则 | 图片可见性 = 引用它的笔记中**最宽**的可见性（public 优先） | 无独立图片开关 |

## 5. 页面 ↔ 接口对照（前端与 QA 的核对表）

| 页面 | 接口 |
|-|-|
| P-01/P-02 | Cognito SRP（`amazon-cognito-identity-js`），无自建登录接口 |
| P-03 | `GET /notes`、`GET /dirs` |
| P-04 | `GET/PUT/DELETE /notes/{id}`、A1–A4 |
| P-05 | 复用 `PUT /notes/{id}`（412 `data` 五件套） |
| P-06 | V1–V3 |
| P-07 | A3–A5 |
| P-08 | `GET /shares?scope=incoming`、`GET /notes` |
| P-09 | H1–H3、**N7** |
| P-10 | `GET /dirs`（trash 分支）、恢复 job、**N6** |
| P-11 | `GET /search` |
| P-12/P-13 | M1–M7 |
| P-14 | P1/P2 + Cognito ChangePassword |
| P-15 | J1、E2 |
| P-16 | 随 `PUT /notes/{id}` 落 Frontmatter |
| P-19/P-20/P-21 | `POST /notes`、`DELETE /notes/{id}`、`POST /notes` |
| P-22 | E1/E2 |
| P-25 | `POST /trash/purge` |
| P-26 | `POST /notes/{id}/visibility` |
| `/p/{token}` | **N8（匿名）** |

## 6. 待冻结（迭代 0 内必须定稿）

1. 路由键：`GET/POST/PATCH/DELETE /dirs`、`POST /dirs/restore`、`GET /jobs/{id}`、`GET/PUT /profile`、`GET/PUT /admin/team-config`、`GET /assets`、`GET /notes/{id}/versions/{ts}`、**N7/N8 前缀**。
2. `jobs` 全字段（当前为建议 schema）。
3. 错误码全表与三语 key（`error_codes.py` 为唯一真源）。
4. N8 限流维度与阈值（`PUBLIC_RATE_LIMITED`）。

## 7. 契约测试最低要求（交给 T4 执行）

- 每条路由：1 个 2xx + 1 个 4xx，断言 `code` 与 `params` 形状。
- 每个写接口：缺 `If-Match`、错误 `If-Match`、并发改各一例。
- 每个列表接口：`page_size` 越界（0/101）+ `has_more` 正确。
- N8：无凭证 200；撤销后 404；`assets/private` 匿名直连 403。
- 所有 4xx 的 `code` 必须存在于三语 key 表，否则 CI 失败。
