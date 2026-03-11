# mihomo-cli

mihomo (Clash Meta) 命令行管理工具，适用于 WSL 环境。

## 安装

```bash
# 复制到 WSL 中
cp mihomo-cli.sh /usr/local/bin/mihomo-cli
chmod +x /usr/local/bin/mihomo-cli
```

## 依赖

**必需：**
- `jq` — JSON 解析
- `curl` — API 请求

**可选：**
- `python3` — 配置文件编辑（添加/删除/修改订阅）
- `bat` — 配置文件高亮显示

```bash
sudo apt install jq curl python3
```

## 使用方式

### 交互模式

直接运行进入菜单式交互界面：

```bash
mihomo-cli
```

### 命令模式

```bash
# 服务管理
mihomo-cli status          # 查看服务状态
mihomo-cli start           # 启动服务
mihomo-cli stop            # 停止服务
mihomo-cli restart         # 重启服务
mihomo-cli log             # 查看实时日志

# 代理管理
mihomo-cli proxies         # 查看所有节点
mihomo-cli groups          # 查看代理组
mihomo-cli select          # 交互式切换节点
mihomo-cli delay 节点名    # 测试单个节点延迟
mihomo-cli delay-test      # 测试代理组延迟

# 订阅管理
mihomo-cli subs            # 查看订阅信息（含流量/到期）
mihomo-cli update-subs     # 更新订阅
mihomo-cli add-sub         # 添加新订阅
mihomo-cli del-sub         # 删除订阅
mihomo-cli edit-sub-url    # 修改订阅 URL

# 配置管理
mihomo-cli mode            # 查看/切换模式 (rule/global/direct)
mihomo-cli mode global     # 直接切换到全局模式
mihomo-cli reload          # 重载配置（先验证再加载）
mihomo-cli edit            # 用编辑器打开配置文件
mihomo-cli config          # 查看配置文件内容

# 其他
mihomo-cli connections     # 查看当前连接
mihomo-cli rules           # 查看路由规则
mihomo-cli info            # 查看运行信息
mihomo-cli test            # 连通性测试 (Google/GitHub/Baidu)
mihomo-cli dns example.com # DNS 查询
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MIHOMO_CONFIG` | `/home/sunyuchao/.config/mihomo/config.yaml` | 配置文件路径 |
| `MIHOMO_SERVICE` | `mihomo` | systemd 服务名称 |
| `MIHOMO_BIN` | `/usr/local/bin/mihomo` | mihomo 二进制路径 |

## 工作原理

- **服务管理**：通过 `systemctl` 控制 systemd 服务
- **代理/订阅管理**：通过 mihomo RESTful API（`external-controller`）
- **配置编辑**：使用 python3 安全修改 YAML 配置文件
- **延迟测试**：通过 API 发起 HTTP 延迟测试

## 注意事项

- 配置文件中需设置 `external-controller` 才能使用 API 功能
- 修改配置文件后需要执行 `reload` 才能生效
- 服务管理命令需要 sudo 权限
