# SuperSonic Docker 启动指南

## 前置条件

- Docker Desktop 已安装
- Docker Compose 已安装

## 启动步骤

### 1. 配置 Docker 镜像加速器（国内用户必需）

由于 Docker Hub 连接问题，需要配置国内镜像源。

**方式一：通过 Docker Desktop GUI**

1. 打开 **Docker Desktop**
2. 点击 **Settings** → **Docker Engine**
3. 添加以下配置：

```json
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://dockerpull.org",
    "https://dockerhub.icu"
  ]
}
```

4. 点击 **Apply & Restart**

**方式二：手动拉取镜像（备选方案）**

```bash
# 从国内镜像源拉取并重新打标签
docker pull docker.1ms.run/pgvector/pgvector:pg17
docker tag docker.1ms.run/pgvector/pgvector:pg17 pgvector/pgvector:pg17

docker pull docker.1ms.run/supersonicbi/supersonic:latest
docker tag docker.1ms.run/supersonicbi/supersonic:latest supersonicbi/supersonic:latest
```

### 2. 启动服务

```bash
cd docker
docker-compose up -d
```

### 3. 验证启动状态

```bash
# 查看服务状态
docker-compose ps

# 查看 HTTP 响应
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9080
```

### 4. 访问应用

**Web UI**: http://localhost:9080

## 配置说明

### 端口映射

| 服务 | 容器端口 | 主机端口 |
|------|---------|---------|
| SuperSonic | 9080 | 9080 |
| PostgreSQL | 5432 | 15432 |

### 环境变量配置

| 变量名 | 值 | 说明 |
|--------|-----|------|
| S2_DB_TYPE | postgres | 数据库类型（注意：不是 postgresql） |
| S2_DB_HOST | supersonic_postgres | 数据库主机 |
| S2_DB_PORT | 5432 | 数据库端口 |
| S2_DB_DATABASE | postgres | 数据库名称 |
| S2_DB_USER | supersonic_user | 数据库用户 |
| S2_DB_PASSWORD | supersonic_password | 数据库密码 |

**重要说明**：
- `S2_DB_TYPE` 必须设置为 `postgres`，而不是 `postgresql`
- 这是因为配置文件名是 `application-postgres.yaml`
- Spring Boot 根据 profile 名称加载对应的配置文件

### docker-compose.yml 完整配置

```yaml
services:
  supersonic_postgres:
    image: pgvector/pgvector:pg17
    privileged: true
    container_name: supersonic_postgres
    environment:
      LANG: 'C.UTF-8'
      POSTGRES_ROOT_PASSWORD: root_password
      POSTGRES_DATABASE: postgres
      POSTGRES_USER: supersonic_user
      POSTGRES_PASSWORD: supersonic_password
    ports:
      - "15432:5432"
    networks:
      - supersonic_network
    dns:
      - 114.114.114.114
      - 8.8.8.8
      - 8.8.4.4
    healthcheck:
      test: ["CMD-SHELL", "sh -c 'pg_isready -U supersonic_user -d postgres'"]
      interval: 10s
      timeout: 10s
      retries: 5

  supersonic_standalone:
    image: supersonicbi/supersonic:latest
    privileged: true
    container_name: supersonic_standalone
    environment:
      S2_DB_TYPE: postgres
      S2_DB_HOST: supersonic_postgres
      S2_DB_PORT: 5432
      S2_DB_DATABASE: postgres
      S2_DB_USER: supersonic_user
      S2_DB_PASSWORD: supersonic_password
    ports:
      - "9080:9080"
    depends_on:
      supersonic_postgres:
        condition: service_healthy
    networks:
      - supersonic_network
    dns:
      - 114.114.114.114
      - 8.8.8.8
      - 8.8.4.4

networks:
  supersonic_network:
```

## 常见问题

### 1. 镜像拉取失败

**错误信息**：
```
Error response from daemon: Get "https://registry-1.docker.io/v2/": net/http: request canceled
```

**解决方案**：配置 Docker 镜像加速器（见上方步骤1）

### 2. 应用启动失败 - 缺少数据源配置

**错误信息**：
```
Could not resolve placeholder 'spring.datasource.driver-class-name'
```

**解决方案**：
- 确保 `S2_DB_TYPE` 设置为 `postgres`（不是 `postgresql`）
- 确保所有 `S2_DB_*` 环境变量正确配置

### 3. 数据库连接失败

**错误信息**：
```
getConnection but jdbcUrl is not set,jdbcUrl=null,username=null
```

**解决方案**：
- 检查环境变量名称是否正确（使用 `S2_DB_*` 前缀）
- 确保 PostgreSQL 容器健康状态正常

## 日志查看

```bash
# 查看 SuperSonic 日志
docker exec supersonic_standalone tail -100 /usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/s2-info.log

# 查看错误日志
docker exec supersonic_standalone tail -100 /usr/src/app/supersonic-standalone-1.0.0-SNAPSHOT/logs/s2-error.log

# 查看 docker-compose 日志
docker-compose logs -f supersonic_standalone
```

## 常用命令

```bash
# 停止服务
docker-compose down

# 重启服务
docker-compose restart

# 重新构建并启动
docker-compose up -d --build

# 进入容器
docker exec -it supersonic_standalone bash
docker exec -it supersonic_postgres psql -U supersonic_user -d postgres
```

## 修改记录

### 2025-12-25 - 初始配置修复

**问题1：Docker Hub 连接超时**
- 原因：网络连接问题
- 解决：配置国内镜像源（docker.1ms.run）

**问题2：环境变量名称不匹配**
- 原配置：`DB_HOST`, `DB_NAME`, `DB_USERNAME`
- 修正为：`S2_DB_HOST`, `S2_DB_DATABASE`, `S2_DB_USER`
- 原因：application-postgres.yaml 中使用 `S2_DB_*` 前缀

**问题3：Profile 名称错误**
- 原配置：`S2_DB_TYPE: postgresql`
- 修正为：`S2_DB_TYPE: postgres`
- 原因：配置文件名是 `application-postgres.yaml`，不是 `application-postgresql.yaml`
