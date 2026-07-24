# GlitchTip 自建部署（Azure）— 崩溃/hang 收集后端

自建的开源崩溃/hang 收集服务（GlitchTip，Sentry 协议兼容），供 iOS 端
sentry-cocoa 上报。数据留在项目所有者掌控的 Azure，不离自有基础设施。

见 [ADR-0013](adr/0013-self-hosted-glitchtip-sentry-cocoa.md)。

## 部署概览

| 项 | 值 |
|----|----|
| Azure 订阅 | `Visual Studio Enterprise 订阅`（tianpli@outlook.com，`5983a176-1117-4840-82c5-49677d8a09aa`）|
| Resource Group | `rg-vitalstride-glitchtip` |
| 区域 | East Asia（香港，测试员在中国，延迟最低）|
| GlitchTip 版本 | v6.2.2 |
| **服务 URL** | `https://glitchtip-web.wonderfulriver-644a3e45.eastasia.azurecontainerapps.io` |

### 资源清单

| 资源 | 类型 | 规格 |
|------|------|------|
| `vitalstride-glitchtip-pg` | PostgreSQL Flexible Server | Standard_B1ms, PG16, 32GB, db `glitchtip` |
| `vitalstride-glitchtip-env` | Container Apps Environment | + Log Analytics |
| `glitchtip-redis` | Container App（internal, TCP 6379）| redis:7-alpine, 0.25vCPU/0.5Gi |
| `glitchtip-web` | Container App（external 443）| glitchtip/glitchtip:latest, 0.5vCPU/1Gi, 1-2 replica |
| `glitchtip-worker` | Container App（internal）| 同镜像 `./bin/run-celery-with-beat.sh`, 0.5vCPU/1Gi |

**成本估算**: ~$15-25/月（PG B1ms ~$12-15 + Container Apps 按用量），VS Enterprise $150/月额度覆盖。

## 密钥管理

**不进 repo。** `SECRET_KEY` / PG 密码 / `DATABASE_URL` / `REDIS_URL` 通过
`az containerapp secret`（secretref）注入,创建时用 `openssl rand` 生成。
如需查看:`az containerapp secret list -g rg-vitalstride-glitchtip -n glitchtip-web`。

## 复现部署（az CLI）

```bash
# 0. 切订阅
az account set --subscription 5983a176-1117-4840-82c5-49677d8a09aa

# 1. Resource group
az group create -n rg-vitalstride-glitchtip -l eastasia

# 2. 生成密钥（本地，不进 git）
PGPASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
SECRET=$(openssl rand -base64 48 | tr -d '\n')

# 3. PostgreSQL Flexible（~7min）
az postgres flexible-server create \
  -g rg-vitalstride-glitchtip -n vitalstride-glitchtip-pg -l eastasia \
  --admin-user gtadmin --admin-password "$PGPASS" \
  --sku-name Standard_B1ms --tier Burstable --storage-size 32 \
  --version 16 --database-name glitchtip --public-access 0.0.0.0 --yes

# 4. Container Apps Environment
az containerapp env create \
  -n vitalstride-glitchtip-env -g rg-vitalstride-glitchtip -l eastasia
# → 记下 defaultDomain（如 wonderfulriver-644a3e45.eastasia.azurecontainerapps.io）

# 5. Redis（internal）
az containerapp create -n glitchtip-redis -g rg-vitalstride-glitchtip \
  --environment vitalstride-glitchtip-env --image redis:7-alpine \
  --target-port 6379 --ingress internal --transport tcp \
  --min-replicas 1 --max-replicas 1 --cpu 0.25 --memory 0.5Gi

# 6. Web（external）— DBURL/REDISURL 见下
DBURL="postgres://gtadmin:${PGPASS}@vitalstride-glitchtip-pg.postgres.database.azure.com:5432/glitchtip?sslmode=require"
REDISURL="redis://glitchtip-redis:6379/0"   # 短名！完整 internal FQDN 会 TCP 超时（见坑 #1）
WEBFQDN="glitchtip-web.<defaultDomain>"
az containerapp create -n glitchtip-web -g rg-vitalstride-glitchtip \
  --environment vitalstride-glitchtip-env --image glitchtip/glitchtip:latest \
  --target-port 8080 --ingress external --min-replicas 1 --max-replicas 2 \
  --cpu 0.5 --memory 1.0Gi \
  --secrets "db-url=${DBURL}" "redis-url=${REDISURL}" "secret-key=${SECRET}" \
  --env-vars DATABASE_URL=secretref:db-url REDIS_URL=secretref:redis-url \
    SECRET_KEY=secretref:secret-key "GLITCHTIP_DOMAIN=https://${WEBFQDN}" \
    PORT=8080 GLITCHTIP_MAX_EVENT_LIFE_DAYS=90 \
    ENABLE_OPEN_USER_REGISTRATION=True "ALLOWED_HOSTS=${WEBFQDN}"

# 7. Worker（internal, celery）
az containerapp create -n glitchtip-worker -g rg-vitalstride-glitchtip \
  --environment vitalstride-glitchtip-env --image glitchtip/glitchtip:latest \
  --command "./bin/run-celery-with-beat.sh" \
  --min-replicas 1 --max-replicas 1 --cpu 0.5 --memory 1.0Gi \
  --secrets "db-url=${DBURL}" "redis-url=${REDISURL}" "secret-key=${SECRET}" \
  --env-vars DATABASE_URL=secretref:db-url REDIS_URL=secretref:redis-url \
    SECRET_KEY=secretref:secret-key "GLITCHTIP_DOMAIN=https://${WEBFQDN}" \
    GLITCHTIP_MAX_EVENT_LIFE_DAYS=90
```

DB migration **不会**由 web 镜像自动执行（web 返回 200 只是登录页；空库时事件接收会 500）。必须手动跑 migrate + 处理下面的 Azure 特有坑。

## ⚠️ Azure 特有坑（部署时踩过，务必照做）

GlitchTip v6 用自研 Rust DB 后端（`gt_rust.django_backend`）+ 声明式分区表，与 Azure PostgreSQL Flexible 有几处不兼容，按序解决:

### 1. Redis 地址必须用短名（否则事件接收 500）

Container Apps 同环境内部 TCP 服务互访**只能用短服务名**，完整 `*.internal.<domain>` FQDN 对 TCP 连接超时。`REDIS_URL` 必须是:
```
redis://glitchtip-redis:6379/0        ✅ 通（PONG）
redis://glitchtip-redis.internal.<domain>:6379/0   ❌ timed out → envelope 500
```
web + worker 的 `REDIS_URL` 都要用短名。

### 2. PostgreSQL 扩展 allowlist（migrate 卡 issue_events）

GlitchTip 的 `TrigramExtension` 要 `CREATE EXTENSION pg_trgm`，Azure PG 默认禁扩展，且**扩展名要小写**:
```bash
az postgres flexible-server parameter set \
  -g rg-vitalstride-glitchtip -s vitalstride-glitchtip-pg \
  --name azure.extensions --value "pg_trgm,btree_gin,btree_gist,citext,hstore,uuid-ossp,pgcrypto"
```

### 3. migrate 需手动跑，且 fake 掉分区+tsvector 那条

Rust 后端执行 `issue_events.0001_squashed_0006_replace_tsvector_function`（分区表 + tsvector function）时 ConnectionError。手动装扩展后，用一次性 Container App Job 跑:
```
python manage.py migrate issue_events 0001_squashed_0006_replace_tsvector_function --fake \
  && python manage.py migrate --no-input
```
（该 migration 的 DDL——UUIDv7 RANGE 分区表 + `append_and_limit_tsvector` function——在正常 PostgreSQL 上能建；fake 后其余 163 个 migration 正常应用，共 339 表。）

### 4. superuser + org + project 用 psql 直建

Rust 后端在 `manage.py shell` 里 sync/async ORM 都 ConnectionError。绕开 Django，用 psycopg 直接 INSERT `users_user`（Django pbkdf2_sha256 密码哈希可纯 Python 算）+ `organizations_ext_organization` + `organizations_ext_organizationuser`(**role=3=owner**，见下方警告) + `organizations_ext_organizationowner` + `teams_team` + `projects_project` + `projects_projectkey`。DSN = `https://<projectkey.public_key去连字符>@<web-fqdn>/<project.id>`。

> ⚠️ **两个手填值必须正确，否则 web 后台整站 500（事件接收正常但 dashboard 打不开）——见坑 #5。**
> - `organizations_ext_organizationuser.role` = **3**（`OWNER`）。`OrganizationUserRole` 是 `IntegerChoices`：`MEMBER=0 / ADMIN=1 / MANAGER=2 / OWNER=3`。role 被当**下标**索引 `ROLES` 元组，填 4 会越界 → `/api/0/organizations/<slug>/` 抛 `IndexError: tuple index out of range`。
> - `users_user.email` 用**合法邮箱**，**不要用 `.local` / `.internal` 等保留 TLD**。新版 GlitchTip 用 pydantic 校验响应里的 email，保留 TLD 直接被判非法 → `/api/0/users/me/` 抛 `value is not a valid email address`。

> **本次已建**: 管理员 `tianpli@outlook.com`（密码在部署机 `/tmp/glitchtip-secrets/admin_pass.txt`）、org `VitalStride`、project `VitalStride-iOS`(id=1)、`organizationuser.role=3`。事件接收已验证 HTTP 200，worker 正常消费，web dashboard 登录正常。

### 5. web 后台整站 500 = 坑 #4 手填值非法（事件接收却正常）

**症状**: 浏览器打开 GlitchTip web 后台，静态页能加载（HTTP 200）但整站不可用——每个 API 调用
（`/api/0/users/me/`、`/api/0/organizations/<slug>/`）都 500。控制台还会刷一堆 `Applying inline
style … Content Security Policy` 告警——**那是无害噪音，不是根因**，别被带偏。

**根因**: 坑 #4 用 psql 直建 admin/org 时两个手填值非法（新版 GlitchTip 用 pydantic 校验 API 响应）：
- `organizationuser.role=4` → 越界 → org 接口 `IndexError: tuple index out of range`（正确 `OWNER=3`）。
- admin email 用 `.local` 保留 TLD → users/me 接口 `value is not a valid email address`。

**定位**: 拉 web 日志看真实堆栈（CSP 告警在浏览器控制台，500 堆栈在容器日志）：
```bash
az account set --subscription 5983a176-1117-4840-82c5-49677d8a09aa   # 先切订阅，az 上下文常漂
az containerapp logs show -g rg-vitalstride-glitchtip -n glitchtip-web --tail 60
```

**修复**: 两条 DB UPDATE（web 镜像自带 psycopg，起一次性 Container App Job 跑，复用 web 的 db-url secret）：
```python
cur.execute("UPDATE users_user SET email=%s WHERE email=%s", (NEW_EMAIL, "admin@vitalstride.local"))
cur.execute("UPDATE organizations_ext_organizationuser SET email=%s WHERE email='admin@vitalstride.local'", (NEW_EMAIL,))
cur.execute("UPDATE organizations_ext_organizationuser SET role=3 WHERE role=4")
```
改 email 会改变**登录名**（密码不变）。修后匿名打两个接口应从 500 变 401（未授权，即后端不再崩）。

## 拿 DSN

DSN 已生成（见上「本次已建」+ 部署机 `/tmp/glitchtip-secrets/dsn.txt`）。若需重建 project key，用坑 #4 的 psql 方式。DSN 形如:
   `https://<publicKey>@glitchtip-web.wonderfulriver-644a3e45.eastasia.azurecontainerapps.io/1`

**建议关闭开放注册**（本次用 psql 直建管理员，无需开放注册）:
   ```bash
   az containerapp update -g rg-vitalstride-glitchtip -n glitchtip-web \
     --set-env-vars ENABLE_OPEN_USER_REGISTRATION=False
   ```

DSN 的 public key 可公开（不是密钥），但仍走配置注入 iOS，不硬编码进 git。

## 配置 CI Secrets

TestFlight workflow（`.github/workflows/testflight.yml` 的 `fastlane beta` step）依赖以下 GitHub Secret 才能把 DSN 注入 xcodebuild → Info.plist（`INFOPLIST_KEY_GlitchTipDSN`，具体注入由 MY-1314 完成）。owner 侧必须在 workflow 首次跑之前配置，否则 fail-fast 会拦下 build。

### GLITCHTIP_DSN

值 = 上文「拿 DSN」段生成的完整 GlitchTip Sentry DSN（形如 `https://<publicKey>@<host>/<project-id>`；权威定义见 `specs/015-glitchtip-crash-reporting/spec.md` FR-4）。**不复制明文到本文件或 git 任何位置。**

```bash
# 从 /tmp/glitchtip-secrets/dsn.txt 读回明文并注入 owner repo secret
gh secret set GLITCHTIP_DSN --repo LeePepe/VitalStride < /tmp/glitchtip-secrets/dsn.txt
```

- 缺失时 workflow 里的 fail-fast（`GLITCHTIP_DSN secret 未设置`）会立即失败，不会浪费一整轮 build/上传。
- 轮换：重跑上面这条 `gh secret set` 命令（GitHub 会覆盖旧值），下一次 TestFlight schedule 自动取新值。
- 责权隔离：本 secret 仅供 `fastlane beta` step 消费；`GLITCHTIP_AUTH_TOKEN` / `GLITCHTIP_URL` 由 dSYM 上传链路使用，TODO: MY-1315 补。

## 运维

- **日志**: `az containerapp logs show -g rg-vitalstride-glitchtip -n glitchtip-web --tail 50`
- **重启**: `az containerapp revision restart ...`
- **删全部**（清账单）: `az group delete -n rg-vitalstride-glitchtip --yes`
- **备份**: PG Flexible 默认 7 天自动备份。
- **dSYM 上传**（符号化崩溃栈）: 发版后 `sentry-cli upload-dif --url https://<web>/ --auth-token <token> <dSYM路径>`。CI testflight.yml 可加此步骤。

## 待办

- [ ] 手动注册管理员 + 建 project 拿 DSN（见上）
- [ ] DSN 交给 iOS 接入 issue（Part C）
- [ ] 可选:配 EMAIL_URL（发告警邮件）、自定义域名
