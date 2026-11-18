# 仓墨部署运维

## 1. 运行环境

| 项 | 要求 |
| --- | --- |
| 操作系统 | Windows 10/11 / Server 2019+ x64；Linux x64（glibc 2.25+） |
| 运行时 | 仓颉 1.2.1 运行时（随工具链安装）；Linux 需 OpenSSL 开发库 |
| 端口 | 默认 8080，可配置 |
| 磁盘 | 程序 + 数据；附件和备份按量预留 |
| 内存 | 建议 ≥512MB；文章/附件量大时增加 |

Windows 使用 CNG（`bcrypt.dll`）做 PBKDF2 与 CSPRNG；Linux x64 使用 OpenSSL（`libcrypto`）与 `getrandom(2)`。`cjpm.toml` 已按 target 配置链接选项。

## 2. 构建与启动

```powershell
$env:CANGJIE_HOME = "C:\Program Files (x86)\Cangjie"
$env:Path = "$env:CANGJIE_HOME\runtime\lib\windows_x86_64_cjnative;$env:CANGJIE_HOME\lib\windows_x86_64_cjnative;$env:CANGJIE_HOME\bin;$env:CANGJIE_HOME\tools\bin;$env:CANGJIE_HOME\tools\lib;$env:Path"

cd E:\apps\cangmo
cjpm build

# 前台运行
.\target\release\bin\main.exe serve --host 127.0.0.1 --port 8080 --data E:\apps\cangmo-data
```

构建产物：`target\release\bin\main.exe`。运行时需要仓颉运行时 DLL（工具链的 `runtime\lib\windows_x86_64_cjnative` 已在 PATH）。

### Linux

```bash
# Debian / Ubuntu
sudo apt-get update && sudo apt-get install -y libssl-dev
# Fedora / RHEL: sudo dnf install -y openssl-devel

source /path/to/cangjie/envsetup.sh
cd /opt/cangmo
cjpm build
./target/release/bin/main serve --host 127.0.0.1 --port 8080 --data /var/lib/cangmo
```

也可使用 `./scripts/start.sh`（自动构建并启动）。Linux 产物为 `target/release/bin/main`，无 `.exe` 后缀。部署前请确认 `ldd target/release/bin/main` 能找到 `libcrypto.so` 与仓颉运行时。

## 3. 目录与权限

```text
E:\apps\cangmo\             程序、主题、模板
E:\apps\cangmo-data\        运行时数据（不要放进 Web 根目录）
├─ db.json
├─ wal.log
├─ uploads\
├─ logs\
└─ backups\
```

- 服务账户对数据目录有读写权限；其他用户只读/不可读。
- 不要把 `data/`、`config.json` 提交到 Git 或放入反向代理的静态目录。
- 建议数据目录与程序目录分离，升级时不覆盖数据。

## 4. 反向代理（强烈推荐）

### Caddy

```caddyfile
blog.example.com {
    encode zstd gzip
    reverse_proxy 127.0.0.1:8080 {
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-For {remote_host}
        header_up Host {host}
    }
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        -Server
    }
}
```

### Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name blog.example.com;

    ssl_certificate     /etc/letsencrypt/live/blog.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/blog.example.com/privkey.pem;

    client_max_body_size 26m;

    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;
    }
}
```

代理后设置：

```powershell
$env:CANGMO_TRUST_PROXY = "true"
$env:CANGMO_COOKIE_SECURE = "true"
```

并在 `config.json` 的 `security.allowedHosts` 中填写域名，抵御 Host 头攻击。

## 5. 注册为 Windows 服务

### 方案 A：`sc.exe`

```powershell
sc.exe create CangmoBlog binPath= "E:\apps\cangmo\target\release\bin\main.exe serve --config E:\apps\cangmo-data\config.json" start= auto
sc.exe description CangmoBlog "Cangmo blog engine"
sc.exe failure CangmoBlog reset= 86400 actions= restart/5000/restart/10000/restart/30000
sc.exe start CangmoBlog
```

> `sc.exe` 不设置工作目录；建议用绝对路径 `--config` 与 `--data`，并确保主题/模板路径为绝对路径或在 `config.json` 中配置绝对 `themesDir`、`adminDir`。

### 方案 B：NSSM / WinSW

```powershell
nssm install CangmoBlog "E:\apps\cangmo\target\release\bin\main.exe" "serve --config E:\apps\cangmo-data\config.json"
nssm set CangmoBlog AppDirectory "E:\apps\cangmo"
nssm set CangmoBlog AppStdout "E:\apps\cangmo-data\logs\stdout.log"
nssm set CangmoBlog AppStderr "E:\apps\cangmo-data\logs\stderr.log"
nssm start CangmoBlog
```

## 6. 环境变量

| 变量 | 说明 |
| --- | --- |
| `CANGMO_HOST` | 监听地址，默认 `127.0.0.1` |
| `CANGMO_PORT` | 端口 |
| `CANGMO_DATA_DIR` | 数据目录 |
| `CANGMO_CONFIG` | 配置文件路径 |
| `CANGMO_SECRET` | 覆盖 `security.secret` |
| `CANGMO_SETUP_TOKEN` | 固定初始化令牌 |
| `CANGMO_DEV` | 开发模式（模板热加载、错误详情） |
| `CANGMO_TRUST_PROXY` | 信任 `X-Forwarded-*` |
| `CANGMO_COOKIE_SECURE` | 强制 Secure Cookie |
| `CANGMO_PASSWORD` | CLI 创建用户时的密码 |

## 7. 备份与恢复

### 后台

「工具与备份」→ 创建备份 → 下载 JSON；恢复需上传 JSON 并输入 `RESTORE`。恢复会覆盖全部数据，请先备份。

### CLI

```powershell
.\main.exe backup before-upgrade --config E:\apps\cangmo-data\config.json
.\main.exe export E:\backup\cangmo-export.json --config E:\apps\cangmo-data\config.json
```

### 附件

备份 `data/uploads/` 目录；建议与 JSON 备份一起打包到异地存储。

### 恢复演练

1. 停止服务；
2. 复制当前 `data/` 到临时目录；
3. 后台恢复或 `doctor` 验证；
4. 启动服务，检查首页、后台、RSS；
5. 保留旧数据目录直到确认无误。

## 8. 升级

1. 备份 `data/` 与 `config.json`；
2. 停止服务；
3. 替换程序目录（保留 `data/`、`themes/`、`resources/` 的自定义修改）；
4. `cjpm build`；
5. 启动并运行 `cangmo doctor`；
6. 检查 `/healthz`、首页、后台、登录；
7. 出问题回滚程序目录与 `data/` 备份。

## 9. 监控

| 指标 | 方式 |
| --- | --- |
| 存活 | `GET /healthz` 返回 `{"status":"ok"}` |
| 错误 | `data/logs/app-*.log` 中 `[ERROR]` |
| 磁盘 | 数据目录、备份目录 |
| 证书 | 反向代理层 |
| 备份 | 检查 `data/backups` 最新文件时间 |

## 10. 故障排查

| 现象 | 排查 |
| --- | --- |
| 启动报端口占用 | `netstat -ano \| findstr :8080`，结束占用进程或换端口 |
| 页面 500 | 查看日志最后 `[ERROR]`；开发模式可显示详细错误 |
| 模板缺失 | 确认 `themes/<name>/templates` 与 `resources/admin/templates` 存在，运行 `doctor` |
| 登录后立即退出 | 检查系统时间、`config.json` 的 `secret`、Cookie Secure 与 HTTPS |
| 上传失败 | 检查文件类型/大小、`data/uploads` 权限 |
| 初始化页 403 | 检查 `CANGMO_SETUP_TOKEN`/日志令牌，以及 CSRF 是否被代理缓存 |
| 反向代理后 IP 都是 127.0.0.1 | 设置 `trustProxy=true` 并正确传递 `X-Forwarded-For` |
