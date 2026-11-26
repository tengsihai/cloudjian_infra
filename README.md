# cloudjian-infra — 云笺基础设施工程（T1）

> 依据：技术架构 v1.2、方案 v1.13.7 §12、T1 交付说明 v0.1、任务拆解 v0.1
> **全部门文档入口（新人先读）**：[docs/README.md](docs/README.md)
> **只创建资源与门禁，不创建 Lambda/Layer，不部署 VPC，不 `s3 sync` 前端产物。**

## 仓库结构

```text
cloudjian-infra/
├── main.tf / providers.tf / backend.tf / variables.tf   # 单环境根配置（workspace=tokyo）
├── network.tf                                           # 网络装配入口（空）
├── modules/
│   ├── network/       # 空模块 + VPC 演进接线说明（enable_vpc=false）
│   ├── storage/       # INF-01/02 桶、生命周期、策略、OAC、CORS
│   ├── cdn/           # INF-03 CloudFront + Function
│   ├── cognito/       # INF-04
│   ├── apigw/         # INF-05 HTTP API 壳（API/Stage/JWT/CORS，路由归 backend）
│   ├── iam/           # INF-06
│   ├── ssm/           # INF-07 参数总线
│   ├── scheduler/     # INF-08
│   └── observability/ # INF-09 日志、告警、Budgets
├── scripts/
│   ├── bootstrap_state.sh   # 状态桶一次性创建（唯一手工建桶入口）
│   └── verify_static.sh     # P-00 静态门禁（账户ID/Lambda/VPC/prefix）
├── .github/workflows/       # INF-10 流水线
└── docs/                    # 方案、契约、任务拆解
```

## 首次搭建

```bash
# 1. 状态桶 bootstrap（幂等）
./scripts/bootstrap_state.sh

# 2. 初始化 + workspace
terraform init
terraform workspace new tokyo   # 已存在则跳过

# 3. 静态门禁
./scripts/verify_static.sh

# 4. 计划
terraform plan
```

## 五条红线（违反任一 = 阻断合入）

1. 不建 `$default` 路由（OPTIONS 会被拦成 401，CORS 全废）——**backend CI** 校验；
2. `GET /public/notes/{public_token}`（N8）单独 NONE，不挂 JWT——**backend CI** 校验；
3. 生命周期只用标签 `cj:retention=30d/1d`，不用前缀（`prefix` 字面匹配，命中 0 个不报错）；
4. CDN 白名单只放 `/web/*` 与 `users/*/assets/public/*`，私有路径 403 终态；
5. TF 不得出现 `aws_lambda_function` / `aws_lambda_layer_version`（含 `aws_lambda_permission`——add-permission 归 backend）。

静态断言：`./scripts/verify_static.sh` + `./scripts/verify_apigw_shell.sh`（infra 不建路由/集成、不枚举函数名）；红线 1/2 的路由面校验归 backend CI（契约 §2.6）。

## SSM 参数变更触发清单

参数前缀 `/cloudjian/<key>`，每条 key 只有一个写入方（infra 除 `release/backend|frontend` 外全部）。
**参数变更后，受影响方需各跑一次发布才生效**：

| 变更参数 | 需要重跑 |
|-|-|
| `cdn-domain` | frontend（构建注入 + 失效）、infra（CORS/桶策略 SourceArn 同 PR 内联动） |
| `api-url` | frontend |
| `user-pool-id` / `client-id` | frontend、backend |
| `bucket` | backend、frontend |
| `lambda-exec-role-arn` / `api-id` | backend |
| 其它 | 先查架构 10.2 读取方矩阵 |

前后端 CI **第一步**校验所需参数存在，缺失即失败并提示「请先执行 infra 流水线」。

## 演练栈隔离

破坏性变更（生命周期/桶策略）先在演练栈造数验证：

- 资源前缀 `cloudjian-drill-*`，SSM 前缀 `/cloudjian-drill/*`
- **禁止**沿用 `cloudjian-*`：销毁 drill 栈会误删线上参数


## 调度与告警（P-08）

### 三条 Schedule（INF-08）

| 调度 | 频率（JST） | task |
|-|-|-|
| `cloudjian-daily-reconcile` | 每日 01:00 | `daily_reconcile` |
| `cloudjian-daily-index-check` | 每日 03:00 | `daily_index_check` |
| `cloudjian-weekly-contract` | 每周一 04:00 | `weekly_contract` |

目标 ARN 固定 `...:function:cloudjian-maintenance-api:live`（可推导字符串，**不校验函数存在**）。
弹性窗口 60 分钟；retry 2 次 / 1h。

**函数未就绪窗口（8.4）**：backend 首次发布前调度直调会失败（可读错误，不反复告警轰炸——
所有告警 `treat_missing_data=notBreaching`）；**首发布 maintenance 后转绿**。
发布失败依赖 T3 CI 打点 `CloudJian/PublishFailed`（未打点前告警不触发）。

### 告警与预算基线（交接 T4）

- 函数日志组与 30 天保留：**backend 部署时**创建并设置（infra 不枚举函数）
- 告警动作 → SNS `cloudjian-alarms`（邮件订阅 = `budget_alert_emails`）
- 平台告警清单：API 5xx、CF 5xx%、412 冲突、JOB_RUNNING、SHARE_REVOKED、PublishFailed
- **JOB_RUNNING / SHARE_REVOKED 走 backend EMF 指标**（namespace `CloudJian`），不计入 5xx 口径
- Budgets：`cloudjian` $5/月，ACTUAL 80%/100%（有邮箱才挂通知）
- Cost Allocation Tags：`Project` / `Component` / `Environment` / `ManagedBy` Active

实测：`./scripts/verify_p08_live.sh`（apply 后）


## 流水线（INF-10）

| workflow | 触发 | 部署 | 要点 |
|-|-|-|-|
| `ci.yml` | PR → `dev` | 否 | lint（无凭证）→ plan（`environment: dev`）→ **资源计数**贴 PR 评论 |
| `deploy.yml` | push `dev` | **是** | `gh pr list --state merged` 查不到 SHA 即失败；apply 后结构/live 门禁；策略/CDN 变更触发匿名穿透 |
| `release.yml` | push `main` | 否 | 打 tag + CHANGELOG 片段 + 写 `/cloudjian/release/archive`；**零 apply** |
| `drift.yml` | 每周一 03:00 UTC | 否 | `plan -detailed-exitcode`，有差异开 Issue（label `drift`） |
| `state-backup.yml` | 每月 1 日 | 否 | `s3 sync` 状态桶 → artifact 90 天 |

硬约束：

- **凡带 AWS 凭证的 job 必须 `environment: dev`**（OIDC sub 口径）；纯 lint 不声明。
- 禁 `pull_request_target`；全部 `uses:` 按 **40 位 commit SHA** 锁。
- 仓库需配置 GitHub Environment `dev` + Variable `AWS_TERRAFORM_ROLE_ARN`
  （`arn:aws:iam::<acct>:role/cloudjian-gha-terraform-role`）。
- 本地复跑：`bash scripts/verify_ci_structure.sh`；plan 摘要：`python scripts/plan_summary.py plan.json`。

## 分支与发布

- `feat/*` → PR：fmt/validate/tflint/checkov + plan 摘要（不部署）
- `dev`（PR 合入）：唯一部署环境（dev 即线上）；合入前 CI 全绿
- `main`：只打 tag + 写 `/cloudjian/release/archive`，零部署
- 所有带 AWS 凭证的 job 必须声明 `environment: dev`（OIDC sub 口径）
- 分支保护：dev/main 必须 PR + CI 全绿 + **Include administrators**

## 文档

| 文档 | 用途 |
|-|-|
| [任务拆解 v0.1](docs/云笺-T1-团队-任务拆解-v0.1.md) | P-00…P-09 PR 级 checklist 与 G1–G7 门禁 |
| [交付说明 v0.1](docs/云笺-T1-团队-交付说明-v0.1.md) | 职责一览与必读章节 |
| [技术架构 v1.2](docs/云笺-ALL-基线-技术架构-v1.2.md) | 契约真源（§10 部署、§11 安全） |
| [共同接口契约 v0.1](docs/云笺-ALL-契约-接口契约-v0.1.md) | 路由/错误码/待冻结项 |
