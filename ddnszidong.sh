#!/usr/bin/env bash
set -euo pipefail

SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/dz100001/vless-optimize/main/ddnszidong.sh}"
INSTALL_PATH="/root/aws.sh"
LOG_PATH="/root/aws.log"

usage() {
    cat <<'EOF'
用法（单次执行）:
  aws.sh <auth_email> <auth_key> <zone_name> <record_name> [ip]

用法（一键安装定时任务）:
  aws.sh --install-cron <auth_email> <auth_key> <zone_name> <record_name> [ip]
EOF
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "缺少依赖命令: $1" >&2
        exit 1
    }
}

json_val() {
    local raw="$1" key="$2" scope="${3:-}"
    local hay="$raw"
    local tail

    if [[ "$scope" == "result0" ]]; then
        hay="$(printf '%s' "$raw" | sed -nE 's/.*"result"[[:space:]]*:[[:space:]]*\[[[:space:]]*\{/\{/; s/\}[[:space:]]*\].*//p' | head -n1)"
        if [[ -z "$hay" ]]; then
            printf ''
            return
        fi
    fi

    tail="${hay#*\"$key\"}"
    if [[ "$tail" == "$hay" ]]; then
        printf ''
        return
    fi
    tail="${tail#*:}"
    tail="$(printf '%s' "$tail" | sed -E 's/^[[:space:]]+//')"

    if [[ "$tail" =~ ^\"([^\"]*)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "$tail" =~ ^(true|false|null|-?[0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return
    fi

    printf ''
}

json_errors_message() {
    printf '%s' "$1" | sed -nE 's/.*"message"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n1
}

setup_cf_headers() {
    cf_headers=()
    if [[ -n "${CF_API_TOKEN:-}" ]]; then
        cf_headers+=(-H "Authorization: Bearer ${CF_API_TOKEN}")
    else
        cf_headers+=(-H "X-Auth-Email: ${auth_email}")
        cf_headers+=(-H "X-Auth-Key: ${auth_key}")
    fi
    cf_headers+=(-H "Content-Type: application/json")
}

cf_fail_help() {
    local code="$1"
    echo "Cloudflare API 返回 HTTP ${code}。" >&2
    echo "若为 403/401：第二参数必须是全局 API 密钥；若你只有 API 令牌，请执行: export CF_API_TOKEN='令牌' 并将前两参数改为 -" >&2
}

cf_http_get() {
    local url="$1"
    local tmp body code
    tmp="$(mktemp)"
    code="$(curl -sS -o "$tmp" -w "%{http_code}" -X GET "$url" "${cf_headers[@]}")" || {
        rm -f "$tmp"
        return 1
    }
    body="$(cat "$tmp")"
    rm -f "$tmp"
    case "$code" in
        200) printf '%s' "$body" ;;
        *)
            echo "请求失败: GET $url" >&2
            echo "响应: $body" >&2
            local errm
            errm="$(json_errors_message "$body")"
            [[ -n "$errm" ]] && echo "API 说明: $errm" >&2
            cf_fail_help "$code"
            exit 1
            ;;
    esac
}

cf_http_body() {
    local method="$1"
    local url="$2"
    local data="$3"
    local tmp body code
    tmp="$(mktemp)"
    code="$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "$url" "${cf_headers[@]}" --data "$data")" || {
        rm -f "$tmp"
        return 1
    }
    body="$(cat "$tmp")"
    rm -f "$tmp"
    case "$code" in
        200|201) printf '%s' "$body" ;;
        *)
            echo "请求失败: $method $url" >&2
            echo "响应: $body" >&2
            local errm
            errm="$(json_errors_message "$body")"
            [[ -n "$errm" ]] && echo "API 说明: $errm" >&2
            cf_fail_help "$code"
            exit 1
            ;;
    esac
}

run_once() {
    setup_cf_headers

    local current_ip="${ip:-}"
    local zone_resp zone_success zone_identifier
    local record_url record_resp record_success
    local record_identifier record_content record_proxied
    local create_payload create_resp create_success
    local update_payload update_resp update_success

    if [[ -z "$current_ip" ]]; then
        current_ip="$(curl -fsS https://ipv4.icanhazip.com | tr -d '[:space:]')"
    fi

    if ! [[ "$current_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "IP 不是有效 IPv4: $current_ip" >&2
        exit 1
    fi

    zone_resp="$(cf_http_get "$(curl -sS -o /dev/null -w '%{url_effective}' -G 'https://api.cloudflare.com/client/v4/zones' --data-urlencode "name=${zone_name}")")"
    zone_success="$(json_val "$zone_resp" "success")"
    if [[ "$zone_success" != "true" ]]; then
        echo "查询 Zone 失败: $zone_resp" >&2
        exit 1
    fi

    zone_identifier="$(json_val "$zone_resp" "id" result0)"
    if [[ -z "$zone_identifier" ]]; then
        echo "未找到 Zone: $zone_name" >&2
        exit 1
    fi

    record_url="$(curl -sS -o /dev/null -w '%{url_effective}' -G \
        "https://api.cloudflare.com/client/v4/zones/${zone_identifier}/dns_records" \
        --data-urlencode "type=A" \
        --data-urlencode "name=${record_name}")"
    record_resp="$(cf_http_get "$record_url")"
    record_success="$(json_val "$record_resp" "success")"
    if [[ "$record_success" != "true" ]]; then
        echo "查询 DNS 记录失败: $record_resp" >&2
        exit 1
    fi

    record_identifier="$(json_val "$record_resp" "id" result0)"
    record_content="$(json_val "$record_resp" "content" result0)"
    record_proxied="$(json_val "$record_resp" "proxied" result0)"
    if [[ -z "$record_proxied" ]]; then
        record_proxied="false"
    fi

    if [[ -z "$record_identifier" ]]; then
        create_payload="$(printf '{"type":"A","name":"%s","content":"%s","ttl":1,"proxied":false}' "$record_name" "$current_ip")"
        create_resp="$(cf_http_body POST "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records" "$create_payload")"
        create_success="$(json_val "$create_resp" "success")"
        if [[ "$create_success" != "true" ]]; then
            echo "创建记录失败: $create_resp" >&2
            exit 1
        fi
        echo "已创建记录: $record_name -> $current_ip"
        exit 0
    fi

    if [[ "$record_content" == "$current_ip" ]]; then
        echo "记录已是目标 IPv4，无需更新: $record_name -> $current_ip"
        exit 0
    fi

    update_payload="$(printf '{"type":"A","name":"%s","content":"%s","ttl":1,"proxied":%s}' "$record_name" "$current_ip" "$record_proxied")"
    update_resp="$(cf_http_body PUT "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" "$update_payload")"
    update_success="$(json_val "$update_resp" "success")"
    if [[ "$update_success" != "true" ]]; then
        echo "更新记录失败: $update_resp" >&2
        exit 1
    fi

    echo "已更新记录: $record_name $record_content -> $current_ip"
}

install_cron() {
    require_cmd crontab
    require_cmd curl
    require_cmd chmod

    curl -fsSLo "$INSTALL_PATH" "$SCRIPT_URL"
    chmod +x "$INSTALL_PATH"

    local cron_line existing
    if [[ -n "${CF_API_TOKEN:-}" ]]; then
        cron_line="* * * * * CF_API_TOKEN='${CF_API_TOKEN}' /bin/bash ${INSTALL_PATH} - - ${zone_name} ${record_name}"
    else
        cron_line="* * * * * /bin/bash ${INSTALL_PATH} ${auth_email} ${auth_key} ${zone_name} ${record_name}"
    fi

    if [[ -n "${ip:-}" ]]; then
        cron_line="${cron_line} ${ip}"
    fi

    cron_line="${cron_line} >> ${LOG_PATH} 2>&1"

    existing="$(crontab -l 2>/dev/null || true)"
    existing="$(printf '%s\n' "$existing" \
        | grep -Fv "$INSTALL_PATH" \
        | grep -Fv "/root/setDomainRecorder.sh" \
        | grep -Fv "https://9987.kuaiyun11.com/setDomainRecorder.sh" \
        || true)"

    (printf '%s\n' "$existing"; printf '%s\n' "$cron_line") | crontab -

    echo "已安装脚本到: $INSTALL_PATH"
    echo "已写入定时任务: 每分钟执行一次"

    if [[ -n "${CF_API_TOKEN:-}" ]]; then
        CF_API_TOKEN="${CF_API_TOKEN}" /bin/bash "$INSTALL_PATH" - - "$zone_name" "$record_name" ${ip:+$ip}
    else
        /bin/bash "$INSTALL_PATH" "$auth_email" "$auth_key" "$zone_name" "$record_name" ${ip:+$ip}
    fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "--install-cron" ]]; then
    if [[ $# -lt 5 || $# -gt 6 ]]; then
        echo "参数数量错误，需 5 或 6 个位置参数" >&2
        usage
        exit 1
    fi

    auth_email="$2"
    auth_key="$3"
    zone_name="$4"
    record_name="$5"
    ip="${6:-}"

    require_cmd curl
    require_cmd sed

    if [[ -z "${CF_API_TOKEN:-}" ]]; then
        if [[ "$auth_email" == "-" || "$auth_email" == "x" ]] || [[ "$auth_key" == "-" || "$auth_key" == "x" ]]; then
            echo "未设置 CF_API_TOKEN 时，不能使用占位符作为邮箱或密钥。" >&2
            exit 1
        fi
    fi

    install_cron
    exit 0
fi

if [[ $# -lt 4 || $# -gt 5 ]]; then
    echo "参数数量错误，需 4 或 5 个位置参数" >&2
    usage
    exit 1
fi

auth_email="$1"
auth_key="$2"
zone_name="$3"
record_name="$4"
ip="${5:-}"

require_cmd curl
require_cmd sed

if [[ -z "${CF_API_TOKEN:-}" ]]; then
    if [[ "$auth_email" == "-" || "$auth_email" == "x" ]] || [[ "$auth_key" == "-" || "$auth_key" == "x" ]]; then
        echo "未设置 CF_API_TOKEN 时，不能使用占位符作为邮箱或密钥。" >&2
        exit 1
    fi
fi

run_once
