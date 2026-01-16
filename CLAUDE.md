# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SuperSonic is an AI+BI platform unifying Chat BI (LLM-powered) and Headless BI (semantic layer). Built with Java 21, Spring Boot 3.2.4, React frontend.

## Architecture

**Modular Monolith:** `launchers` → `chat`/`headless` → `common` → `auth`

**Chat Pipeline:** User Query → Schema Mapper (HanLP NLP) → Semantic Parser (Rule/LLM) → Translator (Calcite) → Query Executor

**Semantic Layer:** Domain → Model → Metrics/Dimensions → Dataset

**Key Files:**
- `chat/server/src/main/java/.../ChatQueryService.java` - Pipeline entry
- `headless/server/src/main/java/.../facade/service/impl/S2ChatLayerService.java` - Orchestration
- `headless/core/src/main/java/.../translator/DefaultSemanticTranslator.java` - SQL generation
- `headless/server/src/main/java/.../aspect/S2DataPermissionAspect.java` - Three-level auth (dataset/column/row)

## Common Commands

```bash
# Build
mvn clean package -DskipTests -Dspotless.skip=true
mvn spotless:apply

# Run
./assembly/bin/supersonic-daemon.sh start
./assembly/bin/supersonic-daemon.sh start chat
./assembly/bin/supersonic-daemon.sh stop

# Test
mvn test
mvn test -Dtest=ClassName
mvn test -pl headless/core
```

## Naming Conventions

- Data Objects: `*DO.java`
- Mappers: `*Mapper.java` + `*Mapper.xml`
- API: `*Req.java`, `*Resp.java`
- Services: `*Service.java`, `*ServiceImpl.java`

## Database

Configure via `S2_DB_TYPE` env (h2/mysql/postgresql). Supports MySQL, ClickHouse, DuckDB, Presto, Trino, Kyuubi. Mapper locations: `classpath:mappers/custom/*.xml`, `classpath*:/mappers/*.xml`

## LLM Integration

LangChain4j 0.35.0 with OpenAI, Azure, Ollama, Qianfan, Zhipu AI, DashScope, ChatGLM. Embedding models: BGE, MiniLM. Vector stores: Chroma, Milvus, PGVector.

## API Docs

Swagger at `http://localhost:9080/swagger-ui.html`

## Component Discovery

Use `ComponentFactory` (Spring Factories Loader) for `QueryOptimizer`, `QueryExecutor`, `QueryAccelerator`, `QueryParser` implementations via `META-INF/spring.factories`.
