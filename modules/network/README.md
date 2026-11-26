# modules/network — 空模块与 VPC 演进接线说明

## 现状（方案 12.6 决策）

**云笺不建 VPC。** Lambda 运行在默认网络，经公网访问 S3 / Cognito / API Gateway / CloudWatch。

- 本模块**不包含**任何 `aws_vpc` / `aws_subnet` / `aws_nat_gateway` / `aws_vpc_endpoint` 资源。
- 根配置 `enable_vpc` 默认 `false`，且被 `check "vpc_not_implemented"` 锁死：置 `true` 会在 validate 阶段失败，防止「开了开关却没实现」。
- 安全边界与 VPC 无关，由三项构成：执行角色最小权限、桶策略精确前缀、前端永不直连 S3。

## 为什么当初不建

| 判断项 | 结论 |
|-|-|
| 必须进 VPC 的资源 | 无：无自建库/缓存/中间件 |
| Lambda 在 VPC 内出网 | 只有 NAT 一条路；Cognito 无 VPC Endpoint |
| 代价 | NAT Gateway +$45/月；NAT 实例 +$4/月但引入单点；IPv6 双栈未验证 |

## 演进接线（真到必须上 VPC 时）

前置条件（方案 12.6.3）：

1. 确认合规条款接受「Lambda 落私有子网」；
2. 接受 NAT 实例单点并配健康检查自动重启；
3. 预发演练栈跑通三项验收：Cognito JWKS 可达、S3 Gateway Endpoint 可达、CloudWatch 可写。

接线步骤：

1. 删除 `check "vpc_not_implemented"`；
2. 在本模块实现：
   - 2 公有子网 + 2 私有子网（跨 2 AZ，`ap-northeast-1` a/c）；
   - NAT 实例（非 Gateway，省 $41/月）+ 用户数据健康检查；
   - `aws_vpc_endpoint` S3 Gateway Endpoint（路由表挂 `pl-xxxx` 前缀列表）；
   - 输出：`vpc_id`、`public_subnet_ids`、`private_subnet_ids`、`nat_instance_id`、`s3_endpoint_id`；
3. backend 发布流水线给 6 个函数加 `vpc_config`（业务代码无需改动）；
4. 演练栈（`cloudjian-drill-*`）先验证，再上 `cloudjian-*`。

成本：约 +$4/月（NAT 实例档）。

## 演练栈隔离（方案 12.8）

临时演练必须用独立命名与独立参数前缀：

- 资源：`cloudjian-drill-*`
- SSM：`/cloudjian-drill/*`

**禁止**沿用 `cloudjian-*` / `/cloudjian/*`：会与线上互相覆盖，销毁 drill 栈时会误删线上参数。
