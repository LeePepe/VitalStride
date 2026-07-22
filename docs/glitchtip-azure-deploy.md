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
REDISURL="redis://glitchtip-redis.internal.<defaultDomain>:6379/0"
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

DB migration 由 web 镜像启动时自动执行（返回 200 即完成）。

## 拿 DSN（需手动，一次性）

1. 浏览器打开 `https://glitchtip-web.wonderfulriver-644a3e45.eastasia.azurecontainerapps.io`
2. **Register** 注册第一个账号（这是管理员）。邮箱 + 密码自定。
3. 建 **Organization**（如 `VitalStride`）→ 建 **Project**，Platform 选 **Apple / iOS**。
4. Project → Settings → **Client Keys (DSN)** → 复制 DSN，形如:
   `https://<publicKey>@glitchtip-web.wonderfulriver-644a3e45.eastasia.azurecontainerapps.io/<projectId>`
5. **注册后建议关闭开放注册**（防陌生人注册）:
   ```bash
   az containerapp update -g rg-vitalstride-glitchtip -n glitchtip-web \
     --set-env-vars ENABLE_OPEN_USER_REGISTRATION=False
   ```

DSN 的 public key 可公开（不是密钥），但仍走配置注入 iOS，不硬编码进 git。

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
