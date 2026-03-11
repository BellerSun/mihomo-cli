#!/bin/bash
#
# mihomo-cli: mihomo (Clash Meta) 命令行管理工具
# 适用于 WSL 环境
#

# ======================== 配置 ========================
CONFIG_FILE="${MIHOMO_CONFIG:-/home/sunyuchao/.config/mihomo/config.yaml}"
SERVICE_NAME="${MIHOMO_SERVICE:-mihomo}"
MIHOMO_BIN="${MIHOMO_BIN:-/usr/local/bin/mihomo}"

# ======================== 颜色 ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# ======================== API 配置 ========================
API_ADDR=""
API_SECRET=""
PROXY_PORT=""

# ======================== 工具函数 ========================
info()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; }
title()   { echo -e "\n${BOLD}${CYAN}── $* ──${NC}"; }
divider() { printf "${DIM}"; printf '─%.0s' $(seq 1 50); printf "${NC}\n"; }

urlencode() {
    jq -sRr @uri <<< "$1" 2>/dev/null || python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1" 2>/dev/null || echo "$1"
}

bytes_to_human() {
    local bytes=${1:-0}
    if [[ "$bytes" -ge 1073741824 ]]; then
        awk "BEGIN{printf \"%.2f GB\", $bytes/1073741824}"
    elif [[ "$bytes" -ge 1048576 ]]; then
        awk "BEGIN{printf \"%.2f MB\", $bytes/1048576}"
    elif [[ "$bytes" -ge 1024 ]]; then
        awk "BEGIN{printf \"%.2f KB\", $bytes/1024}"
    else
        echo "${bytes} B"
    fi
}

delay_color() {
    local delay=${1:-0}
    if [[ "$delay" -le 0 ]]; then
        echo -e "${RED}超时${NC}"
    elif [[ "$delay" -lt 200 ]]; then
        echo -e "${GREEN}${delay}ms${NC}"
    elif [[ "$delay" -lt 500 ]]; then
        echo -e "${YELLOW}${delay}ms${NC}"
    else
        echo -e "${RED}${delay}ms${NC}"
    fi
}

check_deps() {
    local missing=()
    for cmd in jq curl awk; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "缺少依赖: ${missing[*]}"
        echo "  请安装: sudo apt install ${missing[*]}"
        exit 1
    fi
}

parse_api_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warn "配置文件不存在: $CONFIG_FILE"
        warn "部分功能将不可用"
        API_ADDR="http://127.0.0.1:9090"
        return
    fi

    API_ADDR=$(awk '/^external-controller:/{print $2}' "$CONFIG_FILE" | tr -d "\"'")
    API_SECRET=$(awk '/^secret:/{print $2}' "$CONFIG_FILE" | tr -d "\"'")
    PROXY_PORT=$(awk '/^mixed-port:/{print $2}' "$CONFIG_FILE" | tr -d "\"'")
    [[ -z "$PROXY_PORT" ]] && PROXY_PORT=$(awk '/^port:/{print $2}' "$CONFIG_FILE" | tr -d "\"'")

    [[ -z "$API_ADDR" ]] && API_ADDR="127.0.0.1:9090"
    [[ -z "$PROXY_PORT" ]] && PROXY_PORT="7890"
    [[ "$API_ADDR" != http* ]] && API_ADDR="http://$API_ADDR"
}

# ======================== API 请求 ========================
api_get() {
    if [[ -n "$API_SECRET" ]]; then
        curl -s -H "Authorization: Bearer $API_SECRET" "${API_ADDR}$1" 2>/dev/null
    else
        curl -s "${API_ADDR}$1" 2>/dev/null
    fi
}

api_put() {
    if [[ -n "$API_SECRET" ]]; then
        curl -s -X PUT -H "Authorization: Bearer $API_SECRET" \
            -H "Content-Type: application/json" -d "${2:-{}}" "${API_ADDR}$1" 2>/dev/null
    else
        curl -s -X PUT -H "Content-Type: application/json" \
            -d "${2:-{}}" "${API_ADDR}$1" 2>/dev/null
    fi
}

api_patch() {
    if [[ -n "$API_SECRET" ]]; then
        curl -s -X PATCH -H "Authorization: Bearer $API_SECRET" \
            -H "Content-Type: application/json" -d "${2:-{}}" "${API_ADDR}$1" 2>/dev/null
    else
        curl -s -X PATCH -H "Content-Type: application/json" \
            -d "${2:-{}}" "${API_ADDR}$1" 2>/dev/null
    fi
}

api_delete() {
    if [[ -n "$API_SECRET" ]]; then
        curl -s -X DELETE -H "Authorization: Bearer $API_SECRET" "${API_ADDR}$1" 2>/dev/null
    else
        curl -s -X DELETE "${API_ADDR}$1" 2>/dev/null
    fi
}

check_api() {
    local result
    result=$(api_get "/version" 2>/dev/null)
    [[ -n "$result" ]] && echo "$result" | jq -e . &>/dev/null
}

require_api() {
    if ! check_api; then
        error "API 不可用，请确认 mihomo 服务是否运行"
        return 1
    fi
}

# ======================== 服务管理 ========================
cmd_status() {
    title "服务状态"
    sudo systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || warn "服务未安装或未运行"
}

cmd_start() {
    title "启动服务"
    sudo systemctl start "$SERVICE_NAME" && info "服务已启动" || error "启动失败"
}

cmd_stop() {
    title "停止服务"
    sudo systemctl stop "$SERVICE_NAME" && info "服务已停止" || error "停止失败"
}

cmd_restart() {
    title "重启服务"
    sudo systemctl restart "$SERVICE_NAME" && info "服务已重启" || error "重启失败"
}

cmd_log() {
    title "服务日志 (Ctrl+C 退出)"
    sudo journalctl -u "$SERVICE_NAME" -f --no-pager -n 50
}

# ======================== 版本信息 ========================
cmd_info() {
    title "运行信息"
    require_api || return 1

    local version config_info
    version=$(api_get "/version")
    config_info=$(api_get "/configs")

    echo -e "  ${BOLD}版本:${NC}  $(echo "$version" | jq -r '.version // "未知"')"
    echo -e "  ${BOLD}模式:${NC}  $(echo "$config_info" | jq -r '.mode // "未知"')"
    echo -e "  ${BOLD}端口:${NC}  $(echo "$config_info" | jq -r '."mixed-port" // .port // "未知"')"
    echo -e "  ${BOLD}API:${NC}   $API_ADDR"
    echo -e "  ${BOLD}配置:${NC}  $CONFIG_FILE"
    echo -e "  ${BOLD}密钥:${NC}  ${API_SECRET:+${API_SECRET:0:4}****}"
}

# ======================== 代理节点管理 ========================
cmd_proxies() {
    title "代理节点列表"
    require_api || return 1

    local proxies
    proxies=$(api_get "/proxies")

    local count=0
    echo ""
    printf "  ${BOLD}%-40s %-12s %s${NC}\n" "节点名称" "类型" "延迟"
    divider

    echo "$proxies" | jq -r '
        .proxies | to_entries[] |
        select(.value.type != "Selector" and .value.type != "URLTest" and
               .value.type != "Fallback" and .value.type != "LoadBalance" and
               .value.type != "Direct" and .value.type != "Reject" and
               .value.type != "Compatible" and .value.type != "Pass" and
               .value.type != "Relay" and .value.type != "Dns") |
        "\(.key)|\(.value.type)|\(.value.history[-1].delay // 0)"
    ' 2>/dev/null | sort -t'|' -k1 | while IFS='|' read -r name type delay; do
        local delay_str
        delay_str=$(delay_color "$delay")
        printf "  ${CYAN}%-40s${NC} ${DIM}%-12s${NC} %b\n" "$name" "$type" "$delay_str"
        ((count++))
    done

    echo ""
    local total
    total=$(echo "$proxies" | jq '[.proxies | to_entries[] | select(.value.type != "Selector" and .value.type != "URLTest" and .value.type != "Fallback" and .value.type != "LoadBalance" and .value.type != "Direct" and .value.type != "Reject" and .value.type != "Compatible" and .value.type != "Pass" and .value.type != "Relay" and .value.type != "Dns")] | length' 2>/dev/null)
    echo -e "  共 ${WHITE}${total:-0}${NC} 个节点"
}

cmd_groups() {
    title "代理组"
    require_api || return 1

    local proxies
    proxies=$(api_get "/proxies")

    echo "$proxies" | jq -r '
        .proxies | to_entries[] |
        select(.value.type == "Selector" or .value.type == "URLTest" or
               .value.type == "Fallback" or .value.type == "LoadBalance" or
               .value.type == "Relay") |
        "\(.key)|\(.value.type)|\(.value.now // "无")|\(.value.all | length)"
    ' 2>/dev/null | while IFS='|' read -r name type now count; do
        echo -e "\n  ${BOLD}${CYAN}$name${NC} ${DIM}($type)${NC}"
        echo -e "    当前选择: ${GREEN}$now${NC}"
        echo -e "    节点数量: ${WHITE}$count${NC}"
        divider
    done
}

cmd_select() {
    title "切换节点"
    require_api || return 1

    local proxies
    proxies=$(api_get "/proxies")

    echo -e "\n${BOLD}可选代理组:${NC}"
    local groups=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && groups+=("$line")
    done < <(echo "$proxies" | jq -r '
        .proxies | to_entries[] |
        select(.value.type == "Selector") | .key
    ')

    if [[ ${#groups[@]} -eq 0 ]]; then
        warn "没有找到 Selector 类型的代理组"
        return 1
    fi

    local i=1
    for g in "${groups[@]}"; do
        local current
        current=$(echo "$proxies" | jq -r ".proxies[\"$g\"].now // \"无\"")
        echo -e "  ${WHITE}${i}.${NC} ${g} ${DIM}(当前: ${current})${NC}"
        ((i++))
    done

    echo -ne "\n请选择代理组 [1-${#groups[@]}]: "
    read -r choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt ${#groups[@]} ]]; then
        error "无效选择"
        return 1
    fi

    local group_name="${groups[$((choice-1))]}"

    echo -e "\n${BOLD}${group_name} 的可用节点:${NC}"
    local nodes=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && nodes+=("$line")
    done < <(echo "$proxies" | jq -r ".proxies[\"$group_name\"].all[]" 2>/dev/null)

    if [[ ${#nodes[@]} -eq 0 ]]; then
        warn "该组没有可用节点"
        return 1
    fi

    local current_node
    current_node=$(echo "$proxies" | jq -r ".proxies[\"$group_name\"].now // \"\"")

    i=1
    for n in "${nodes[@]}"; do
        if [[ "$n" == "$current_node" ]]; then
            echo -e "  ${GREEN}${i}. ${n} ◄ 当前${NC}"
        else
            echo -e "  ${WHITE}${i}.${NC} ${n}"
        fi
        ((i++))
    done

    echo -ne "\n请选择节点 [1-${#nodes[@]}]: "
    read -r choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt ${#nodes[@]} ]]; then
        error "无效选择"
        return 1
    fi

    local proxy_name="${nodes[$((choice-1))]}"
    local encoded_group
    encoded_group=$(urlencode "$group_name")

    local result
    result=$(api_put "/proxies/${encoded_group}" "{\"name\":\"${proxy_name}\"}")

    if [[ -z "$result" ]]; then
        info "已切换 ${CYAN}${group_name}${NC} -> ${GREEN}${proxy_name}${NC}"
    else
        local msg
        msg=$(echo "$result" | jq -r '.message // empty' 2>/dev/null)
        if [[ -n "$msg" ]]; then
            error "切换失败: $msg"
        else
            info "已切换 ${CYAN}${group_name}${NC} -> ${GREEN}${proxy_name}${NC}"
        fi
    fi
}

cmd_delay_test() {
    title "测试节点延迟"
    require_api || return 1

    local proxies
    proxies=$(api_get "/proxies")

    local groups=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && groups+=("$line")
    done < <(echo "$proxies" | jq -r '
        .proxies | to_entries[] |
        select(.value.type == "Selector" or .value.type == "URLTest" or
               .value.type == "Fallback") | .key
    ')

    if [[ ${#groups[@]} -eq 0 ]]; then
        warn "没有找到代理组"
        return 1
    fi

    echo -e "\n${BOLD}选择要测试的代理组:${NC}"
    local i=1
    for g in "${groups[@]}"; do
        echo -e "  ${WHITE}${i}.${NC} $g"
        ((i++))
    done
    echo -e "  ${WHITE}0.${NC} 测试全部"

    echo -ne "\n请选择 [0-${#groups[@]}]: "
    read -r choice

    local test_groups=()
    if [[ "$choice" == "0" ]]; then
        test_groups=("${groups[@]}")
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le ${#groups[@]} ]]; then
        test_groups=("${groups[$((choice-1))]}")
    else
        error "无效选择"
        return 1
    fi

    for g in "${test_groups[@]}"; do
        echo -e "\n${BOLD}测试 ${CYAN}$g${NC} ${BOLD}...${NC}"
        local encoded
        encoded=$(urlencode "$g")
        local result
        result=$(api_get "/group/${encoded}/delay?url=http://www.gstatic.com/generate_204&timeout=5000")

        if [[ -z "$result" ]] || ! echo "$result" | jq -e . &>/dev/null; then
            warn "测试失败或超时"
            continue
        fi

        echo "$result" | jq -r 'to_entries[] | "\(.key)|\(.value)"' 2>/dev/null | \
            sort -t'|' -k2 -n | while IFS='|' read -r name delay; do
            local delay_str
            delay_str=$(delay_color "$delay")
            printf "    ${CYAN}%-38s${NC} %b\n" "$name" "$delay_str"
        done
    done
}

cmd_delay_single() {
    local proxy_name="${1:-}"
    if [[ -z "$proxy_name" ]]; then
        echo -ne "请输入节点名称: "
        read -r proxy_name
    fi
    [[ -z "$proxy_name" ]] && { error "节点名称不能为空"; return 1; }

    require_api || return 1

    local encoded_name
    encoded_name=$(urlencode "$proxy_name")

    echo -ne "  测试 ${CYAN}${proxy_name}${NC} ... "
    local result
    result=$(api_get "/proxies/${encoded_name}/delay?timeout=5000&url=http://www.gstatic.com/generate_204")

    local delay
    delay=$(echo "$result" | jq -r '.delay // 0' 2>/dev/null)
    delay_color "$delay"
}

# ======================== 订阅管理 ========================
cmd_subs() {
    title "订阅信息"

    if check_api; then
        local providers
        providers=$(api_get "/providers/proxies")

        local has_http=false
        while IFS='|' read -r name vtype updated upload download total expire proxy_count; do
            [[ -z "$name" ]] && continue
            has_http=true

            echo -e "\n  ${BOLD}${CYAN}${name}${NC}"
            echo -e "    节点数: ${WHITE}${proxy_count}${NC}"
            echo -e "    更新时间: ${updated:-未知}"

            if [[ "${total:-0}" -gt 0 ]]; then
                local used=$(( ${upload:-0} + ${download:-0} ))
                local used_h total_h pct
                used_h=$(bytes_to_human "$used")
                total_h=$(bytes_to_human "$total")
                pct=$(awk "BEGIN{printf \"%.1f\", $used*100/$total}" 2>/dev/null || echo "?")
                echo -e "    已用流量: ${YELLOW}${used_h}${NC} / ${WHITE}${total_h}${NC} (${pct}%)"
            fi

            if [[ "${expire:-0}" -gt 0 ]]; then
                local exp_date
                exp_date=$(date -d "@$expire" '+%Y-%m-%d' 2>/dev/null || echo "未知")
                echo -e "    到期时间: ${exp_date}"
            fi
            divider
        done < <(echo "$providers" | jq -r '
            .providers | to_entries[] |
            select(.value.vehicleType == "HTTP") |
            "\(.key)|\(.value.vehicleType)|\(.value.updatedAt // "")|\(.value.subscriptionInfo.Upload // 0)|\(.value.subscriptionInfo.Download // 0)|\(.value.subscriptionInfo.Total // 0)|\(.value.subscriptionInfo.Expire // 0)|\(.value.proxies | length)"
        ' 2>/dev/null)

        if ! $has_http; then
            warn "没有找到 HTTP 类型的订阅 (proxy-provider)"
        fi
    else
        warn "API 不可用，仅显示配置文件中的信息"
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "\n${BOLD}配置文件中的订阅源:${NC}"
        awk '
            /^proxy-providers:/ { in_pp=1; next }
            in_pp && /^[^ #]/ { in_pp=0 }
            in_pp && /^  [a-zA-Z0-9_-]+:/ {
                name=$1; gsub(/:$/,"",name);
                printf "\n  \033[0;36m%s\033[0m\n", name
            }
            in_pp && /url:/ {
                url=$2; gsub(/["'"'"']/,"",url);
                printf "    URL: \033[2m%s\033[0m\n", url
            }
            in_pp && /interval:/ {
                printf "    更新间隔: %s 秒\n", $2
            }
        ' "$CONFIG_FILE"
    fi
}

cmd_update_subs() {
    title "更新订阅"
    require_api || return 1

    local providers
    providers=$(api_get "/providers/proxies")

    local names=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && names+=("$line")
    done < <(echo "$providers" | jq -r '.providers | to_entries[] | select(.value.vehicleType == "HTTP") | .key' 2>/dev/null)

    if [[ ${#names[@]} -eq 0 ]]; then
        warn "没有找到 HTTP 类型的订阅"
        return 1
    fi

    echo -e "\n可用订阅:"
    local i=1
    for p in "${names[@]}"; do
        echo -e "  ${WHITE}${i}.${NC} $p"
        ((i++))
    done
    echo -e "  ${WHITE}0.${NC} 更新全部"

    echo -ne "\n请选择 [0-${#names[@]}]: "
    read -r choice

    local update_list=()
    if [[ "$choice" == "0" ]]; then
        update_list=("${names[@]}")
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le ${#names[@]} ]]; then
        update_list=("${names[$((choice-1))]}")
    else
        error "无效选择"
        return 1
    fi

    for p in "${update_list[@]}"; do
        echo -ne "  更新 ${CYAN}$p${NC} ... "
        local encoded
        encoded=$(urlencode "$p")
        local result
        result=$(api_put "/providers/proxies/${encoded}" "{}")
        if [[ -z "$result" ]] || echo "$result" | jq -e '.message' &>/dev/null 2>&1; then
            local msg
            msg=$(echo "$result" | jq -r '.message // empty' 2>/dev/null)
            if [[ -n "$msg" ]]; then
                echo -e "${RED}失败: ${msg}${NC}"
            else
                echo -e "${GREEN}成功${NC}"
            fi
        else
            echo -e "${GREEN}成功${NC}"
        fi
    done
}

cmd_add_sub() {
    title "添加订阅"

    [[ ! -f "$CONFIG_FILE" ]] && { error "配置文件不存在: $CONFIG_FILE"; return 1; }

    echo -ne "  订阅名称 (英文): "
    read -r sub_name
    echo -ne "  订阅 URL: "
    read -r sub_url
    echo -ne "  更新间隔 (秒, 默认 3600): "
    read -r sub_interval
    sub_interval=${sub_interval:-3600}

    [[ -z "$sub_name" || -z "$sub_url" ]] && { error "名称和 URL 不能为空"; return 1; }

    if ! command -v python3 &>/dev/null; then
        error "需要 python3 来安全地编辑 YAML 配置"
        echo "  请手动编辑 $CONFIG_FILE 添加订阅"
        return 1
    fi

    python3 - "$CONFIG_FILE" "$sub_name" "$sub_url" "$sub_interval" <<'PYEOF'
import sys

config_file = sys.argv[1]
sub_name = sys.argv[2]
sub_url = sys.argv[3]
sub_interval = sys.argv[4]

with open(config_file, 'r') as f:
    content = f.read()

new_provider = f"""  {sub_name}:
    type: http
    url: "{sub_url}"
    interval: {sub_interval}
    path: ./providers/{sub_name}.yaml
    health-check:
      enable: true
      url: http://www.gstatic.com/generate_204
      interval: 300
"""

lines = content.split('\n')
result = []
inserted = False

if 'proxy-providers:' in content:
    i = 0
    while i < len(lines):
        result.append(lines[i])
        if lines[i].rstrip() == 'proxy-providers:':
            result.append(new_provider.rstrip())
            inserted = True
        i += 1
else:
    result = lines + ['', 'proxy-providers:', new_provider.rstrip()]
    inserted = True

if inserted:
    with open(config_file, 'w') as f:
        f.write('\n'.join(result))
    print('OK')
else:
    print('FAIL')
    sys.exit(1)
PYEOF

    if [[ $? -eq 0 ]]; then
        info "已添加订阅 ${CYAN}${sub_name}${NC}"
        warn "需要重载配置才能生效 (选项 19 或命令: mihomo-cli reload)"
    else
        error "添加失败"
    fi
}

cmd_del_sub() {
    title "删除订阅"
    [[ ! -f "$CONFIG_FILE" ]] && { error "配置文件不存在"; return 1; }

    local subs=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && subs+=("$line")
    done < <(awk '/^proxy-providers:/,/^[^ #]/' "$CONFIG_FILE" | awk '/^  [a-zA-Z0-9_-]+:/{gsub(/:$/,"",$1); print $1}')

    if [[ ${#subs[@]} -eq 0 ]]; then
        warn "配置中没有找到订阅"
        return 1
    fi

    local i=1
    for s in "${subs[@]}"; do
        echo -e "  ${WHITE}${i}.${NC} $s"
        ((i++))
    done

    echo -ne "\n请选择要删除的订阅 [1-${#subs[@]}]: "
    read -r choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt ${#subs[@]} ]]; then
        error "无效选择"
        return 1
    fi

    local sub_name="${subs[$((choice-1))]}"
    echo -ne "  确认删除 ${RED}${sub_name}${NC}? [y/N]: "
    read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { info "已取消"; return 0; }

    if ! command -v python3 &>/dev/null; then
        error "需要 python3 来安全地编辑 YAML 配置"
        return 1
    fi

    python3 - "$CONFIG_FILE" "$sub_name" <<'PYEOF'
import sys

config_file = sys.argv[1]
target = sys.argv[2]

with open(config_file, 'r') as f:
    lines = f.readlines()

result = []
skip = False
target_indent = -1

for line in lines:
    stripped = line.rstrip('\n')
    if not skip:
        # Check if this is the target provider entry (2-space indent)
        if stripped.rstrip() == f'  {target}:':
            skip = True
            target_indent = 2
            continue
        result.append(line)
    else:
        # If line is empty or has deeper indent, skip it
        if stripped == '' or (len(stripped) > 0 and len(stripped) - len(stripped.lstrip()) > target_indent):
            continue
        else:
            skip = False
            result.append(line)

with open(config_file, 'w') as f:
    f.writelines(result)

print('OK')
PYEOF

    if [[ $? -eq 0 ]]; then
        info "已删除订阅 ${CYAN}${sub_name}${NC}"
        warn "需要重载配置才能生效"
    else
        error "删除失败，请手动编辑配置文件"
    fi
}

cmd_edit_sub_url() {
    title "修改订阅 URL"
    [[ ! -f "$CONFIG_FILE" ]] && { error "配置文件不存在"; return 1; }

    local subs=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && subs+=("$line")
    done < <(awk '/^proxy-providers:/,/^[^ #]/' "$CONFIG_FILE" | awk '/^  [a-zA-Z0-9_-]+:/{gsub(/:$/,"",$1); print $1}')

    if [[ ${#subs[@]} -eq 0 ]]; then
        warn "配置中没有找到订阅"
        return 1
    fi

    local i=1
    for s in "${subs[@]}"; do
        local url
        url=$(awk "/^  ${s}:/,/^  [^ ]/" "$CONFIG_FILE" | awk '/url:/{gsub(/["'"'"']/,"",$2); print $2; exit}')
        echo -e "  ${WHITE}${i}.${NC} ${s}"
        echo -e "     ${DIM}${url}${NC}"
        ((i++))
    done

    echo -ne "\n请选择要修改的订阅 [1-${#subs[@]}]: "
    read -r choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt ${#subs[@]} ]]; then
        error "无效选择"
        return 1
    fi

    local sub_name="${subs[$((choice-1))]}"
    echo -ne "  新的 URL: "
    read -r new_url
    [[ -z "$new_url" ]] && { error "URL 不能为空"; return 1; }

    if ! command -v python3 &>/dev/null; then
        error "需要 python3 来安全地编辑 YAML 配置"
        return 1
    fi

    python3 - "$CONFIG_FILE" "$sub_name" "$new_url" <<'PYEOF'
import sys

config_file = sys.argv[1]
target = sys.argv[2]
new_url = sys.argv[3]

with open(config_file, 'r') as f:
    lines = f.readlines()

result = []
in_target = False

for line in lines:
    stripped = line.rstrip('\n')
    if stripped.rstrip() == f'  {target}:':
        in_target = True
        result.append(line)
        continue
    if in_target:
        # Check if we left the provider block
        if stripped and not stripped.startswith('    ') and not stripped.startswith('  '):
            in_target = False
        elif stripped.strip().startswith('url:'):
            indent = len(line) - len(line.lstrip())
            result.append(' ' * indent + f'url: "{new_url}"\n')
            in_target = False
            continue
    result.append(line)

with open(config_file, 'w') as f:
    f.writelines(result)

print('OK')
PYEOF

    if [[ $? -eq 0 ]]; then
        info "已更新 ${CYAN}${sub_name}${NC} 的 URL"
        warn "需要重载配置才能生效"
    else
        error "修改失败"
    fi
}

# ======================== 配置管理 ========================
cmd_mode() {
    require_api || return 1

    local config_info
    config_info=$(api_get "/configs")
    local current
    current=$(echo "$config_info" | jq -r '.mode')

    title "运行模式"
    echo -e "  当前: ${BOLD}${GREEN}${current}${NC}\n"

    local modes=("rule" "global" "direct")
    for m in "${modes[@]}"; do
        if [[ "$m" == "$current" ]]; then
            echo -e "    ${GREEN}● ${m}${NC}"
        else
            echo -e "    ○ ${m}"
        fi
    done

    if [[ -n "${1:-}" ]]; then
        local new_mode="$1"
    else
        echo -ne "\n  切换到 [rule/global/direct] (回车取消): "
        read -r new_mode
        [[ -z "$new_mode" ]] && return 0
    fi

    if [[ "$new_mode" != "rule" && "$new_mode" != "global" && "$new_mode" != "direct" ]]; then
        error "无效模式: $new_mode"
        return 1
    fi

    api_patch "/configs" "{\"mode\":\"$new_mode\"}" >/dev/null
    info "模式已切换: ${GREEN}${new_mode}${NC}"
}

cmd_config_view() {
    title "配置文件"
    echo -e "  路径: ${DIM}${CONFIG_FILE}${NC}\n"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "配置文件不存在"
        return 1
    fi

    if command -v bat &>/dev/null; then
        bat --style=numbers --language=yaml "$CONFIG_FILE"
    elif command -v less &>/dev/null; then
        less "$CONFIG_FILE"
    else
        cat "$CONFIG_FILE"
    fi
}

cmd_edit() {
    local editor="${EDITOR:-${VISUAL:-nano}}"
    title "编辑配置"
    echo -e "  使用 ${BOLD}${editor}${NC} 打开 ${CONFIG_FILE}\n"
    $editor "$CONFIG_FILE"
}

cmd_reload() {
    title "重载配置"

    if [[ -f "$MIHOMO_BIN" ]] || command -v "$MIHOMO_BIN" &>/dev/null; then
        echo -ne "  验证配置 ... "
        local verify
        verify=$("$MIHOMO_BIN" -t -f "$CONFIG_FILE" 2>&1)
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}失败${NC}"
            error "配置验证失败:"
            echo "$verify"
            return 1
        fi
        echo -e "${GREEN}通过${NC}"
    fi

    if check_api; then
        echo -ne "  通过 API 重载 ... "
        local result
        result=$(api_put "/configs?force=true" "{\"path\":\"$CONFIG_FILE\"}")
        local msg
        msg=$(echo "$result" | jq -r '.message // empty' 2>/dev/null)
        if [[ -n "$msg" ]]; then
            echo -e "${RED}失败${NC}"
            error "$msg"
            return 1
        fi
        echo -e "${GREEN}成功${NC}"
    else
        warn "API 不可用，通过重启服务重载"
        cmd_restart
    fi
}

# ======================== 连接管理 ========================
cmd_connections() {
    title "当前连接"
    require_api || return 1

    local conns
    conns=$(api_get "/connections")

    local total upload download
    total=$(echo "$conns" | jq '.connections | length' 2>/dev/null || echo 0)
    upload=$(echo "$conns" | jq '.uploadTotal // 0' 2>/dev/null)
    download=$(echo "$conns" | jq '.downloadTotal // 0' 2>/dev/null)

    echo -e "  活跃连接: ${WHITE}${total}${NC}"
    echo -e "  上传总量: ${GREEN}$(bytes_to_human "${upload:-0}")${NC}"
    echo -e "  下载总量: ${CYAN}$(bytes_to_human "${download:-0}")${NC}"

    if [[ "${total:-0}" -gt 0 ]]; then
        echo -e "\n  ${BOLD}最近 20 条连接:${NC}\n"
        printf "  ${DIM}%-40s %-20s %s${NC}\n" "目标" "链路" "规则"
        divider
        echo "$conns" | jq -r '
            .connections | sort_by(.start) | reverse | .[0:20][] |
            "\(.metadata.host // .metadata.destinationIP):\(.metadata.destinationPort)|\(.chains | join(" → "))|\(.rule)"
        ' 2>/dev/null | while IFS='|' read -r dest chain rule; do
            printf "  %-40s ${CYAN}%-20s${NC} ${DIM}%s${NC}\n" "$dest" "$chain" "$rule"
        done

        echo ""
        echo -ne "  清空所有连接? [y/N]: "
        read -r confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            api_delete "/connections" >/dev/null
            info "已清空所有连接"
        fi
    fi
}

# ======================== 规则 ========================
cmd_rules() {
    title "路由规则"
    require_api || return 1

    local rules
    rules=$(api_get "/rules")
    local count
    count=$(echo "$rules" | jq '.rules | length' 2>/dev/null || echo 0)

    echo -e "  规则总数: ${WHITE}${count}${NC}\n"
    printf "  ${DIM}%-14s %-40s %s${NC}\n" "类型" "匹配" "代理"
    divider

    local show_count=50
    echo "$rules" | jq -r ".rules[0:${show_count}][] | \"\(.type)|\(.payload)|\(.proxy)\"" 2>/dev/null | \
        while IFS='|' read -r type payload proxy; do
            printf "  %-14s %-40s ${CYAN}%s${NC}\n" "$type" "$payload" "$proxy"
        done

    if [[ "$count" -gt "$show_count" ]]; then
        echo -e "\n  ${DIM}... 还有 $((count - show_count)) 条规则${NC}"
    fi
}

# ======================== 连通性测试 ========================
cmd_test() {
    title "连通性测试"

    local proxy_addr="http://127.0.0.1:${PROXY_PORT}"
    echo -e "  使用代理: ${DIM}${proxy_addr}${NC}\n"

    local sites=("Google|https://www.google.com" "GitHub|https://github.com" "YouTube|https://www.youtube.com")
    local direct_sites=("Baidu|https://www.baidu.com")

    for entry in "${sites[@]}"; do
        local name url
        IFS='|' read -r name url <<< "$entry"
        echo -ne "  ${BOLD}${name}${NC} (代理) ... "
        local result
        result=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}" \
            --proxy "$proxy_addr" "$url" --connect-timeout 5 --max-time 10 2>/dev/null)
        local code time_s
        code=$(echo "$result" | cut -d'|' -f1)
        time_s=$(echo "$result" | cut -d'|' -f2)
        if [[ "$code" =~ ^(200|204|301|302)$ ]]; then
            echo -e "${GREEN}成功${NC} (${time_s}s)"
        else
            echo -e "${RED}失败${NC} (HTTP ${code})"
        fi
    done

    for entry in "${direct_sites[@]}"; do
        local name url
        IFS='|' read -r name url <<< "$entry"
        echo -ne "  ${BOLD}${name}${NC} (直连) ... "
        local result
        result=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}" \
            "$url" --connect-timeout 5 --max-time 10 2>/dev/null)
        local code time_s
        code=$(echo "$result" | cut -d'|' -f1)
        time_s=$(echo "$result" | cut -d'|' -f2)
        if [[ "$code" =~ ^(200|204|301|302)$ ]]; then
            echo -e "${GREEN}成功${NC} (${time_s}s)"
        else
            echo -e "${RED}失败${NC} (HTTP ${code})"
        fi
    done
}

# ======================== DNS 查询 ========================
cmd_dns() {
    title "DNS 查询"
    require_api || return 1

    local domain="${1:-}"
    if [[ -z "$domain" ]]; then
        echo -ne "  输入域名: "
        read -r domain
    fi
    [[ -z "$domain" ]] && { error "域名不能为空"; return 1; }

    echo -ne "  查询 ${CYAN}${domain}${NC} ... "
    local result
    result=$(api_get "/dns/query?name=${domain}&type=A")

    if [[ -z "$result" ]]; then
        echo -e "${RED}失败${NC}"
        return 1
    fi

    echo -e "${GREEN}完成${NC}"
    echo "$result" | jq -r '.Answer[]? | "    \(.data) (TTL: \(.TTL)s)"' 2>/dev/null
    if [[ $(echo "$result" | jq '.Answer | length' 2>/dev/null) == "0" ]]; then
        warn "没有查询结果"
    fi
}

# ======================== 交互式菜单 ========================
show_banner() {
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║        mihomo CLI 管理工具 v1.0           ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_menu() {
    clear
    show_banner

    if check_api; then
        local ver mode
        ver=$(api_get "/version" | jq -r '.version // "?"' 2>/dev/null)
        mode=$(api_get "/configs" | jq -r '.mode // "?"' 2>/dev/null)
        echo -e "  ${GREEN}●${NC} 服务运行中  ${DIM}版本: ${ver}  模式: ${mode}${NC}\n"
    else
        echo -e "  ${RED}●${NC} 服务未运行\n"
    fi

    echo -e "  ${BOLD}[服务管理]${NC}"
    echo -e "    ${WHITE} 1${NC}  查看服务状态        ${WHITE} 2${NC}  启动服务"
    echo -e "    ${WHITE} 3${NC}  停止服务            ${WHITE} 4${NC}  重启服务"
    echo -e "    ${WHITE} 5${NC}  查看日志"
    echo ""
    echo -e "  ${BOLD}[代理管理]${NC}"
    echo -e "    ${WHITE} 6${NC}  查看所有节点        ${WHITE} 7${NC}  查看代理组"
    echo -e "    ${WHITE} 8${NC}  切换节点            ${WHITE} 9${NC}  测试节点延迟"
    echo ""
    echo -e "  ${BOLD}[订阅管理]${NC}"
    echo -e "    ${WHITE}10${NC}  查看订阅信息        ${WHITE}11${NC}  更新订阅"
    echo -e "    ${WHITE}12${NC}  添加订阅            ${WHITE}13${NC}  删除订阅"
    echo -e "    ${WHITE}14${NC}  修改订阅 URL"
    echo ""
    echo -e "  ${BOLD}[配置与其他]${NC}"
    echo -e "    ${WHITE}15${NC}  查看/切换模式       ${WHITE}16${NC}  查看当前连接"
    echo -e "    ${WHITE}17${NC}  查看路由规则        ${WHITE}18${NC}  编辑配置文件"
    echo -e "    ${WHITE}19${NC}  重载配置            ${WHITE}20${NC}  查看运行信息"
    echo -e "    ${WHITE}21${NC}  连通性测试          ${WHITE}22${NC}  DNS 查询"
    echo -e "    ${WHITE}23${NC}  查看配置文件"
    echo ""
    echo -e "    ${WHITE} 0${NC}  退出"
    echo ""
}

interactive_mode() {
    while true; do
        show_menu
        echo -ne "  ${BOLD}请选择 [0-23]: ${NC}"
        read -r choice
        echo ""

        case "$choice" in
            1)  cmd_status ;;
            2)  cmd_start ;;
            3)  cmd_stop ;;
            4)  cmd_restart ;;
            5)  cmd_log ;;
            6)  cmd_proxies ;;
            7)  cmd_groups ;;
            8)  cmd_select ;;
            9)  cmd_delay_test ;;
            10) cmd_subs ;;
            11) cmd_update_subs ;;
            12) cmd_add_sub ;;
            13) cmd_del_sub ;;
            14) cmd_edit_sub_url ;;
            15) cmd_mode ;;
            16) cmd_connections ;;
            17) cmd_rules ;;
            18) cmd_edit ;;
            19) cmd_reload ;;
            20) cmd_info ;;
            21) cmd_test ;;
            22) cmd_dns ;;
            23) cmd_config_view ;;
            0)  echo -e "  ${GREEN}再见!${NC}"; exit 0 ;;
            *)  warn "无效选择: $choice" ;;
        esac

        echo ""
        echo -ne "  ${DIM}按回车返回菜单...${NC}"
        read -r
    done
}

# ======================== 帮助 ========================
show_help() {
    show_banner
    echo -e "用法: ${CYAN}$(basename "$0")${NC} [命令] [参数]\n"

    echo -e "${BOLD}服务管理:${NC}"
    echo "  status                查看服务状态"
    echo "  start                 启动服务"
    echo "  stop                  停止服务"
    echo "  restart               重启服务"
    echo "  log                   查看服务日志 (实时)"
    echo ""
    echo -e "${BOLD}代理管理:${NC}"
    echo "  proxies               查看所有代理节点"
    echo "  groups                查看代理组"
    echo "  select                交互式切换节点"
    echo "  delay [节点名]        测试单个节点延迟"
    echo "  delay-test            测试代理组延迟"
    echo ""
    echo -e "${BOLD}订阅管理:${NC}"
    echo "  subs                  查看订阅信息"
    echo "  update-subs           更新订阅"
    echo "  add-sub               添加订阅"
    echo "  del-sub               删除订阅"
    echo "  edit-sub-url          修改订阅 URL"
    echo ""
    echo -e "${BOLD}配置与其他:${NC}"
    echo "  mode [rule|global|direct]  查看/切换模式"
    echo "  connections           查看当前连接"
    echo "  rules                 查看路由规则"
    echo "  config                查看配置文件"
    echo "  edit                  编辑配置文件"
    echo "  reload                重载配置"
    echo "  info                  查看运行信息"
    echo "  test                  连通性测试"
    echo "  dns [域名]            DNS 查询"
    echo ""
    echo -e "${DIM}不带参数运行进入交互模式${NC}"
    echo ""
    echo -e "${BOLD}环境变量:${NC}"
    echo "  MIHOMO_CONFIG         配置文件路径 (默认: $CONFIG_FILE)"
    echo "  MIHOMO_SERVICE        服务名称 (默认: $SERVICE_NAME)"
    echo "  MIHOMO_BIN            二进制路径 (默认: $MIHOMO_BIN)"
}

# ======================== 主入口 ========================
main() {
    check_deps
    parse_api_config

    case "${1:-}" in
        status)         cmd_status ;;
        start)          cmd_start ;;
        stop)           cmd_stop ;;
        restart)        cmd_restart ;;
        log)            cmd_log ;;
        proxies)        cmd_proxies ;;
        groups)         cmd_groups ;;
        select)         cmd_select ;;
        delay)          cmd_delay_single "${2:-}" ;;
        delay-test)     cmd_delay_test ;;
        subs)           cmd_subs ;;
        update-subs)    cmd_update_subs ;;
        add-sub)        cmd_add_sub ;;
        del-sub)        cmd_del_sub ;;
        edit-sub-url)   cmd_edit_sub_url ;;
        mode)           cmd_mode "${2:-}" ;;
        connections)    cmd_connections ;;
        rules)          cmd_rules ;;
        config)         cmd_config_view ;;
        edit)           cmd_edit ;;
        reload)         cmd_reload ;;
        info)           cmd_info ;;
        test)           cmd_test ;;
        dns)            cmd_dns "${2:-}" ;;
        help|-h|--help) show_help ;;
        "")             interactive_mode ;;
        *)              error "未知命令: $1"; echo ""; show_help ;;
    esac
}

main "$@"
