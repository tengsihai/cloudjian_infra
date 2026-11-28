# 网络入口（决策 = 不建 VPC）。
# 本文件只做装配；modules/network 内无任何 aws_vpc / aws_subnet 资源。
# 演进路径见 modules/network/README.md（打开 enable_vpc 前必须先读）。

# 有意留空：enable_vpc = true 时也要求先补齐模块实现，再在此处接线。
