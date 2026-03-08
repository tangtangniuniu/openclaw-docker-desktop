#!/bin/bash
set -e

echo "=== OpenClaw 初始化脚本 ==="

OPENCLAW_USER="${USER:-ubuntu}"
OPENCLAW_HOME="/home/$OPENCLAW_USER/.openclaw"
OPENCLAW_WORKSPACE="${WORKSPACE:-/home/$OPENCLAW_USER/.openclaw/workspace}"

# 创建必要目录
mkdir -p "$OPENCLAW_HOME" "$OPENCLAW_WORKSPACE"

# 首次初始化：从镜像预装位置复制插件
if [ ! -d "$OPENCLAW_HOME/extensions/dingtalk" ]; then
    echo "首次启动，复制预装插件..."
    mkdir -p "$OPENCLAW_HOME/extensions"
    cp -rn /opt/openclaw-extensions/* "$OPENCLAW_HOME/extensions/" 2>/dev/null || true
fi
if [ ! -d "$OPENCLAW_HOME/qqbot" ]; then
    cp -rn /opt/openclaw-qqbot "$OPENCLAW_HOME/qqbot" 2>/dev/null || true
fi

# 修复权限
if [ "$(id -u)" -eq 0 ]; then
    chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "$OPENCLAW_HOME" || true
fi

# 全量同步配置逻辑
sync_config_with_env() {
    local config_file="$OPENCLAW_HOME/openclaw.json"

    # 如果文件不存在，创建一个基础骨架
    if [ ! -f "$config_file" ]; then
        echo "配置文件不存在，创建基础骨架..."
        cat > "$config_file" <<EOF
{
  "meta": { "lastTouchedVersion": "2026.2.14" },
  "update": { "checkOnStart": false },
  "browser": {
    "headless": true,
    "noSandbox": true,
    "defaultProfile": "openclaw",
    "executablePath": "/usr/bin/chromium-browser"
  },
  "models": { "mode": "merge", "providers": { "default": { "models": [] } } },
  "agents": {
    "defaults": {
      "compaction": { "mode": "safeguard" },
      "elevatedDefault": "full",
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 }
    }
  },
  "messages": { "ackReactionScope": "group-mentions", "tts": { "edge": { "voice": "zh-CN-XiaoxiaoNeural" } } },
  "commands": { "native": "auto", "nativeSkills": "auto" },
  "channels": {},
  "plugins": { "entries": {}, "installs": {} },
  "memory": {
    "backend": "qmd",
    "qmd": {
      "command": "/usr/local/bin/qmd",
      "paths": [
        {
          "path": "/home/$OPENCLAW_USER/.openclaw/workspace",
          "name": "workspace",
          "pattern": "**/*.md"
        }
      ]
    }
  }
}
EOF
    fi

    echo "正在根据当前环境变量同步配置状态..."
    OPENCLAW_USER="$OPENCLAW_USER" CONFIG_FILE="$config_file" python3 - <<'PYCODE'
import json, sys, os, re
from datetime import datetime

OPENCLAW_USER = os.environ.get('OPENCLAW_USER', 'ubuntu')
WECOM_ACCOUNT_ID_RE = re.compile(r'^[a-z0-9_-]+$')
WECOM_ACCOUNT_FIELDS = {'token', 'encodingAesKey', 'adminUsers', 'agent', 'webhooks'}
WECOM_RESERVED_FIELDS = {'enabled', 'commands', 'dmPolicy', 'groupPolicy'}


def is_wecom_account_config(v):
    return isinstance(v, dict) and any(k in v for k in WECOM_ACCOUNT_FIELDS)


def normalize_wecom_config(channels):
    wecom = channels.get('wecom')
    if not isinstance(wecom, dict):
        return

    migrated = False
    account_map = {}
    preserved = {k: v for k, v in wecom.items() if k in WECOM_RESERVED_FIELDS}

    for k, v in wecom.items():
        if k in WECOM_RESERVED_FIELDS:
            continue
        if WECOM_ACCOUNT_ID_RE.match(k) and is_wecom_account_config(v):
            account_map[k] = v

    legacy_account = {k: wecom[k] for k in WECOM_ACCOUNT_FIELDS if k in wecom}
    if legacy_account:
        default_cfg = account_map.get('default', {})
        if not isinstance(default_cfg, dict):
            default_cfg = {}
        for k, v in legacy_account.items():
            default_cfg.setdefault(k, v)
        account_map['default'] = default_cfg
        migrated = True

    if account_map:
        new_wecom = {**preserved, **account_map}
        if new_wecom != wecom:
            channels['wecom'] = new_wecom
            migrated = True

    if migrated:
        print('✅ 企业微信配置已标准化为多账号结构（旧单账号已兼容为 default）')


def deep_merge(dst, src):
    if not isinstance(dst, dict) or not isinstance(src, dict):
        return src
    for k, v in src.items():
        if isinstance(v, dict) and isinstance(dst.get(k), dict):
            dst[k] = deep_merge(dst[k], v)
        else:
            dst[k] = v
    return dst


def get_wecom_accounts(wecom):
    if not isinstance(wecom, dict):
        return []
    accounts = []
    for account_id, cfg in wecom.items():
        if account_id in WECOM_RESERVED_FIELDS:
            continue
        if not is_wecom_account_config(cfg):
            continue
        accounts.append((account_id, cfg))
    return accounts


def merge_wecom_bots_from_env(channels, env):
    raw = (env.get('WECOM_BOTS_JSON') or '').strip()
    if not raw:
        return False

    try:
        parsed = json.loads(raw)
    except Exception as ex:
        raise ValueError(f'WECOM_BOTS_JSON 不是合法 JSON: {ex}')

    if not isinstance(parsed, dict):
        raise ValueError('WECOM_BOTS_JSON 必须是对象，格式为 {"bot1": {...}, "bot2": {...}}')

    if 'accounts' in parsed and isinstance(parsed.get('accounts'), dict):
        parsed = parsed['accounts']
    elif 'wecom' in parsed and isinstance(parsed.get('wecom'), dict):
        parsed = parsed['wecom']

    wecom = channels.get('wecom')
    if not isinstance(wecom, dict):
        wecom = {}
        channels['wecom'] = wecom

    changed = False
    for account_id, account_cfg in parsed.items():
        if not WECOM_ACCOUNT_ID_RE.match(str(account_id)):
            raise ValueError(f'WECOM_BOTS_JSON 账号 ID 不合法: {account_id}，仅支持小写字母、数字、-、_')
        if not isinstance(account_cfg, dict) or not is_wecom_account_config(account_cfg):
            raise ValueError(f'WECOM_BOTS_JSON 账号配置非法: {account_id}，至少包含 token/encodingAesKey/agent/webhooks 中的一项')

        old_cfg = wecom.get(account_id)
        if not isinstance(old_cfg, dict):
            old_cfg = {}
        merged = deep_merge(old_cfg, account_cfg)
        wecom[account_id] = merged
        changed = True

    if changed:
        wecom['enabled'] = True
        if 'commands' not in wecom:
            wecom['commands'] = {'enabled': True, 'allowlist': ['/new', '/status', '/help', '/compact']}
        print('✅ 已从 WECOM_BOTS_JSON 同步企业微信多账号配置')
    return changed


def validate_wecom_multi_accounts(channels):
    wecom = channels.get('wecom')
    if not isinstance(wecom, dict):
        return

    accounts = []
    for account_id, cfg in wecom.items():
        if account_id in WECOM_RESERVED_FIELDS:
            continue
        if not is_wecom_account_config(cfg):
            continue
        if not WECOM_ACCOUNT_ID_RE.match(account_id):
            raise ValueError(f'企业微信账号 ID 不合法: {account_id}，仅支持小写字母、数字、-、_')
        accounts.append((account_id, cfg))

    if not accounts:
        return

    token_index = {}
    agent_id_index = {}
    for account_id, cfg in accounts:
        account_token = (cfg.get('token') or '').strip()
        if account_token:
            token_index.setdefault(account_token, []).append(f'{account_id}.token')

        agent = cfg.get('agent') if isinstance(cfg.get('agent'), dict) else None
        if agent:
            callback_token = (agent.get('token') or '').strip()
            if callback_token:
                token_index.setdefault(callback_token, []).append(f'{account_id}.agent.token')

            agent_id = agent.get('agentId')
            if agent_id is not None and str(agent_id).strip() != '':
                agent_id_index.setdefault(str(agent_id).strip(), []).append(account_id)

    duplicate_tokens = {k: v for k, v in token_index.items() if len(v) > 1}
    if duplicate_tokens:
        detail = '; '.join([f"{token}: {', '.join(paths)}" for token, paths in duplicate_tokens.items()])
        raise ValueError(f'企业微信 Token 冲突（可能导致消息路由错乱）: {detail}')

    duplicate_agent_ids = {k: v for k, v in agent_id_index.items() if len(v) > 1}
    if duplicate_agent_ids:
        detail = '; '.join([f"{agent_id}: {', '.join(ids)}" for agent_id, ids in duplicate_agent_ids.items()])
        raise ValueError(f'企业微信 Agent ID 冲突（可能导致消息路由错乱）: {detail}')


def sync():
    path = os.environ.get('CONFIG_FILE', f'/home/{OPENCLAW_USER}/.openclaw/openclaw.json')
    try:
        with open(path, 'r', encoding='utf-8') as f:
            config = json.load(f)

        env = os.environ

        def ensure_path(cfg, keys):
            curr = cfg
            for k in keys:
                if k not in curr: curr[k] = {}
                curr = curr[k]
            return curr

        # --- 0. 飞书旧版本格式迁移 ---
        feishu_raw = config.get('channels', {}).get('feishu', {})
        if 'appId' in feishu_raw and 'accounts' not in feishu_raw:
            print('检测到飞书旧版本格式，执行迁移...')
            old_app_id = feishu_raw.pop('appId', '')
            old_app_secret = feishu_raw.pop('appSecret', '')
            old_bot_name = feishu_raw.pop('botName', 'OpenClaw Bot')
            feishu_raw['accounts'] = {'default': {'appId': old_app_id, 'appSecret': old_app_secret, 'botName': old_bot_name}}

        feishu_accounts = feishu_raw.get('accounts')
        if isinstance(feishu_accounts, dict) and 'main' in feishu_accounts:
            print('检测到飞书 accounts.main，迁移为 accounts.default...')
            main_account = feishu_accounts.pop('main')
            default_account = feishu_accounts.get('default')
            if not isinstance(default_account, dict):
                feishu_accounts['default'] = main_account if isinstance(main_account, dict) else {}
            elif isinstance(main_account, dict):
                for k, v in main_account.items():
                    default_account.setdefault(k, v)

        # --- 0.5 企业微信旧格式迁移 ---
        normalize_wecom_config(ensure_path(config, ['channels']))

        # --- 1. 模型同步 ---
        sync_model = env.get('SYNC_MODEL_CONFIG', 'true').strip().lower()
        if sync_model in ('', 'true', '1', 'yes'):
            def sync_provider(p_name, api_key, base_url, protocol, m_ids_str, context_window, max_tokens):
                if not (api_key and base_url or m_ids_str): return None
                p = ensure_path(config, ['models', 'providers', p_name])
                if api_key: p['apiKey'] = api_key
                if base_url: p['baseUrl'] = base_url
                p['api'] = protocol or 'openai-completions'

                mlist = p.get('models', [])
                m_ids = [x.strip() for x in m_ids_str.split(',') if x.strip()]

                for m_id in m_ids:
                    actual_m_id = m_id
                    m_obj = next((m for m in mlist if m.get('id') == actual_m_id), None)
                    if not m_obj:
                        m_obj = {'id': actual_m_id, 'name': actual_m_id, 'reasoning': False, 'input': ['text', 'image'],
                                 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0}}
                        mlist.append(m_obj)
                    m_obj['contextWindow'] = int(context_window or 200000)
                    m_obj['maxTokens'] = int(max_tokens or 8192)

                p['models'] = mlist
                return p_name

            p1_active = sync_provider(
                'default',
                env.get('API_KEY'),
                env.get('BASE_URL'),
                env.get('API_PROTOCOL'),
                env.get('MODEL_ID') or 'gpt-4o',
                env.get('CONTEXT_WINDOW'),
                env.get('MAX_TOKENS')
            )

            p2_name = env.get('MODEL2_NAME') or 'model2'
            p2_active = sync_provider(
                p2_name,
                env.get('MODEL2_API_KEY'),
                env.get('MODEL2_BASE_URL'),
                env.get('MODEL2_PROTOCOL'),
                env.get('MODEL2_MODEL_ID') or '',
                env.get('MODEL2_CONTEXT_WINDOW'),
                env.get('MODEL2_MAX_TOKENS')
            )

            mid_raw = env.get('MODEL_ID') or 'gpt-4o'
            mid = [x.strip() for x in mid_raw.split(',') if x.strip()][0]

            imid_raw = env.get('IMAGE_MODEL_ID') or mid
            imid = [x.strip() for x in imid_raw.split(',') if x.strip()][0]

            def get_full_mid(m_id, default_p='default'):
                if '/' in m_id: return m_id
                return f'{default_p}/{m_id}'

            if p1_active:
                ensure_path(config, ['agents', 'defaults', 'model'])['primary'] = get_full_mid(mid)
                ensure_path(config, ['agents', 'defaults', 'imageModel'])['primary'] = get_full_mid(imid)

            config['agents']['defaults']['workspace'] = env.get('WORKSPACE') or f'/home/{OPENCLAW_USER}/.openclaw/workspace'

            if 'memory' in config and 'qmd' in config['memory']:
                config['memory']['qmd']['command'] = '/usr/local/bin/qmd'
                for p_item in config['memory']['qmd'].get('paths', []):
                    if p_item.get('name') == 'workspace':
                        p_item['path'] = config['agents']['defaults']['workspace']

            msg = f'✅ 模型同步完成: 主模型={get_full_mid(mid)}'
            if imid != mid: msg += f', 图片模型={get_full_mid(imid)}'
            if p2_active: msg += f', 已启用备用提供商: {p2_name}'
            print(msg)

        # --- 2. 渠道与插件同步 ---
        channels = ensure_path(config, ['channels'])
        plugins = ensure_path(config, ['plugins'])
        entries = ensure_path(plugins, ['entries'])
        installs = ensure_path(plugins, ['installs'])

        if env.get('OPENCLAW_PLUGINS_ENABLED'):
            plugins['enabled'] = env['OPENCLAW_PLUGINS_ENABLED'].lower() == 'true'

        user_home = f'/home/{OPENCLAW_USER}'

        def sync_feishu(c, e):
            c.update({'enabled': True, 'dmPolicy': 'pairing', 'groupPolicy': 'open'})
            default_account = ensure_path(c, ['accounts', 'default'])
            default_account.update({
                'appId': e['FEISHU_APP_ID'],
                'appSecret': e['FEISHU_APP_SECRET'],
                'botName': e.get('FEISHU_BOT_NAME') or 'OpenClaw Bot'
            })
            if e.get('FEISHU_DOMAIN'): default_account['domain'] = e['FEISHU_DOMAIN']

        def sync_dingtalk(c, e):
            c.update({
                'enabled': True, 'clientId': e['DINGTALK_CLIENT_ID'],
                'clientSecret': e['DINGTALK_CLIENT_SECRET'],
                'robotCode': e.get('DINGTALK_ROBOT_CODE') or e['DINGTALK_CLIENT_ID'],
                'dmPolicy': 'open', 'groupPolicy': 'open', 'messageType': 'markdown',
                'allowFrom': ['*']
            })
            if e.get('DINGTALK_CORP_ID'): c['corpId'] = e['DINGTALK_CORP_ID']
            if e.get('DINGTALK_AGENT_ID'): c['agentId'] = e['DINGTALK_AGENT_ID']

        def sync_wecom(c, e):
            c['enabled'] = True
            default_cfg = c.get('default')
            if not isinstance(default_cfg, dict):
                default_cfg = {}
            default_cfg.update({'token': e['WECOM_TOKEN'], 'encodingAesKey': e['WECOM_ENCODING_AES_KEY']})
            c['default'] = default_cfg
            c.pop('token', None)
            c.pop('encodingAesKey', None)
            if 'commands' not in c:
                c['commands'] = {'enabled': True, 'allowlist': ['/new', '/status', '/help', '/compact']}

        sync_rules = [
            (['TELEGRAM_BOT_TOKEN'], 'telegram',
             lambda c, e: c.update({'botToken': e['TELEGRAM_BOT_TOKEN'], 'dmPolicy': 'pairing', 'groupPolicy': 'allowlist', 'streamMode': 'partial'}),
             None),
            (['FEISHU_APP_ID', 'FEISHU_APP_SECRET'], 'feishu', sync_feishu,
             {'source': 'npm', 'spec': '@openclaw/feishu', 'installPath': f'{user_home}/.openclaw/extensions/feishu'}),
            (['DINGTALK_CLIENT_ID', 'DINGTALK_CLIENT_SECRET'], 'dingtalk', sync_dingtalk,
             {'source': 'npm', 'spec': 'https://github.com/soimy/clawdbot-channel-dingtalk.git', 'installPath': f'{user_home}/.openclaw/extensions/dingtalk'}),
            (['QQBOT_APP_ID', 'QQBOT_CLIENT_SECRET'], 'qqbot',
             lambda c, e: c.update({'enabled': True, 'appId': e['QQBOT_APP_ID'], 'clientSecret': e['QQBOT_CLIENT_SECRET']}),
             {'source': 'path', 'sourcePath': f'{user_home}/.openclaw/qqbot', 'installPath': f'{user_home}/.openclaw/extensions/qqbot'}),
            (['NAPCAT_REVERSE_WS_PORT'], 'napcat',
               lambda c, e: c.update({
                   'enabled': True,
                   'reverseWsPort': int(e['NAPCAT_REVERSE_WS_PORT']),
                   **(({'httpUrl': e['NAPCAT_HTTP_URL']}) if e.get('NAPCAT_HTTP_URL') else {}),
                   **(({'accessToken': e['NAPCAT_ACCESS_TOKEN']}) if e.get('NAPCAT_ACCESS_TOKEN') else {}),
                   **(({'admins': [int(x) for x in e['NAPCAT_ADMINS'].split(',') if x.strip()]}) if
 e.get('NAPCAT_ADMINS') else {}),
                   'requireMention': True,
                   'rateLimitMs': 1000,
               }),
               {'source': 'path', 'sourcePath': f'{user_home}/.openclaw/extensions/napcat', 'installPath':
 f'{user_home}/.openclaw/extensions/napcat'}),
            (['WECOM_TOKEN', 'WECOM_ENCODING_AES_KEY'], 'wecom', sync_wecom,
             {'source': 'npm', 'spec': '@sunnoy/wecom', 'installPath': f'{user_home}/.openclaw/extensions/wecom'})
        ]

        for req_envs, cid, config_fn, install_info in sync_rules:
            has_env = all(env.get(k) for k in req_envs)
            if has_env:
                conf_obj = ensure_path(channels, [cid])
                config_fn(conf_obj, env)
                entries[cid] = {'enabled': True}
                if install_info and cid not in installs:
                    install_info['installedAt'] = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'
                    installs[cid] = install_info
                print(f'✅ 渠道同步: {cid}')
            else:
                if cid in entries and entries[cid].get('enabled'):
                    entries[cid]['enabled'] = False
                    print(f'🚫 环境变量缺失，已禁用渠道: {cid}')

        merge_wecom_bots_from_env(channels, env)

        wecom_accounts = get_wecom_accounts(channels.get('wecom'))
        if wecom_accounts:
            entries['wecom'] = {'enabled': True}
            if 'wecom' not in installs:
                installs['wecom'] = {
                    'source': 'npm',
                    'spec': '@sunnoy/wecom',
                    'installPath': f'{user_home}/.openclaw/extensions/wecom',
                    'installedAt': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'
                }

        plugins['allow'] = [k for k, v in entries.items() if v.get('enabled')]
        print('📦 已配置插件集合: ' + ', '.join(plugins['allow']))

        validate_wecom_multi_accounts(channels)

        # --- 3. Gateway 同步 ---
        if env.get('OPENCLAW_GATEWAY_TOKEN'):
            gw = ensure_path(config, ['gateway'])
            gw['port'] = int(env.get('OPENCLAW_GATEWAY_PORT') or 18789)
            gw['bind'] = env.get('OPENCLAW_GATEWAY_BIND') or '0.0.0.0'
            gw['mode'] = env.get('OPENCLAW_GATEWAY_MODE') or 'local'

            cui = ensure_path(gw, ['controlUi'])
            cui['allowInsecureAuth'] = env.get('OPENCLAW_GATEWAY_ALLOW_INSECURE_AUTH', 'true').lower() == 'true'
            cui['dangerouslyDisableDeviceAuth'] = env.get('OPENCLAW_GATEWAY_DANGEROUSLY_DISABLE_DEVICE_AUTH', 'false').lower() == 'true'
            if env.get('OPENCLAW_GATEWAY_ALLOWED_ORIGINS'):
                cui['allowedOrigins'] = [x.strip() for x in env['OPENCLAW_GATEWAY_ALLOWED_ORIGINS'].split(',') if x.strip()]

            auth = ensure_path(gw, ['auth'])
            auth['token'] = env['OPENCLAW_GATEWAY_TOKEN']
            auth['mode'] = env.get('OPENCLAW_GATEWAY_AUTH_MODE') or 'token'

            print('✅ Gateway 同步完成')

        ensure_path(config, ['meta'])['lastTouchedAt'] = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)

    except Exception as e:
        print(f'❌ 同步失败: {e}', file=sys.stderr)
        sys.exit(1)

sync()
PYCODE
}

sync_config_with_env

# 修复权限
if [ "$(id -u)" -eq 0 ]; then
    chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "$OPENCLAW_HOME" || true
fi

echo "=== OpenClaw 初始化完成 ==="
SYNC_CHECK="${SYNC_MODEL_CONFIG:-true}"
SYNC_CHECK=$(echo "$SYNC_CHECK" | tr '[:upper:]' '[:lower:]' | xargs)
if [ "$SYNC_CHECK" = "false" ] || [ "$SYNC_CHECK" = "0" ] || [ "$SYNC_CHECK" = "no" ]; then
    echo "模型配置: 手动模式 (跳过环境变量同步)"
else
    FINAL_MID="${MODEL_ID:-gpt-4o}"
    [[ "$FINAL_MID" != */* ]] && FINAL_MID="default/$FINAL_MID"

    FINAL_IMID="${IMAGE_MODEL_ID:-${MODEL_ID:-gpt-4o}}"
    [[ "$FINAL_IMID" != */* ]] && FINAL_IMID="default/$FINAL_IMID"

    echo "当前主模型: $FINAL_MID"
    echo "当前图片模型: $FINAL_IMID"
    [ -n "$MODEL2_API_KEY" ] && echo "备用提供商: ${MODEL2_NAME:-model2} (已启用)"
fi
echo "API 协议: ${API_PROTOCOL:-openai-completions}"
echo "Base URL: ${BASE_URL}"
echo "上下文窗口: ${CONTEXT_WINDOW:-200000}"
echo "最大 Tokens: ${MAX_TOKENS:-8192}"
echo "Gateway 端口: $OPENCLAW_GATEWAY_PORT"
echo "Gateway 绑定: $OPENCLAW_GATEWAY_BIND"
echo "Gateway 模式: ${OPENCLAW_GATEWAY_MODE:-local}"
echo "插件启用: ${OPENCLAW_PLUGINS_ENABLED:-true}"
