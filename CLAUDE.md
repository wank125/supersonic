# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SuperSonic is a next-generation AI+BI platform that unifies Chat BI (powered by LLM) and Headless BI (powered by semantic layer). It enables natural language querying of data with automatic visualization.

## Architecture

### Key Components

- **Knowledge Base**: Extracts schema information from semantic models and builds dictionaries/indexes
- **Schema Mapper**: Maps natural language to schema elements (metrics/dimensions/entities)
- **Semantic Parser**: Combination of rule-based and LLM-based parsers for query understanding
- **Semantic Corrector**: Validates and corrects semantic queries
- **Semantic Translator**: Converts semantic queries to executable SQL
- **Chat Plugin System**: Extensible architecture for third-party tool integration
- **Chat Memory**: Historical query management for context

### Module Structure

```
supersonic/
├── auth/                    # Authentication & authorization
├── chat/                    # Chat BI module (api/ + server/)
├── headless/               # Headless BI module (api/ + server/ + core/ + chat/)
├── common/                  # Shared utilities
├── launchers/              # Application entry points
│   ├── chat/              # Chat-only launcher
│   ├── headless/          # Headless-only launcher
│   └── standalone/        # Combined application
├── webapp/                # Frontend (React/UmiJS)
└── assembly/              # Build & packaging
```

## Development Commands

### Prerequisites

- Java 21+
- Node.js 16+ with pnpm
- Maven 3.6+

### Backend Development

```bash
# Build all modules (skip tests and formatting for speed)
mvn clean package -DskipTests -Dspotless.skip=true

# Run tests
mvn test

# Run with specific profile
cd launchers/standalone
mvn spring-boot:run -Dspring-boot.run.profiles=local

# Build single module
mvn clean package -pl headless/server -am
```

### Frontend Development

```bash
# Development build
cd webapp
sh start-fe-dev.sh          # Runs on port 9000

# Production build
sh start-fe-prod.sh

# Individual package development
cd webapp/packages/supersonic-fe
pnpm start                  # Alternative dev mode
```

### Application Startup

```bash
# After building backend
cd assembly/bin
./supersonic-daemon.sh start

# Stop
./supersonic-daemon.sh stop
```

## Configuration

- Main config: `launchers/standalone/src/main/resources/application.yaml`
- Database profiles: `application-{h2,mysql,postgres}.yaml`
- Environment configs: `application-{local,prd,docker}.yaml`
- Frontend config: `webapp/packages/supersonic-fe/.umirc.ts`

## Database Support

The project supports multiple databases through Spring profiles:
- **Default**: H2 (in-memory) - use `h2` profile
- **Production**: PostgreSQL with pgvector - use `postgres` profile
- **Alternative**: MySQL - use `mysql` profile

## Key Development Patterns

### LLM Integration

The project uses LangChain4J for LLM integration. Multiple providers are supported:
- OpenAI/Azure OpenAI
- Qianfan (Baidu)
- Zhipu AI
- DashScope (Alibaba)
- Ollama (local)
- ChatGLM

### Testing Strategy

- Unit tests: JUnit 5 with Mockito
- Database tests: Uses H2 in-memory
- Frontend tests: UmiJS test framework
- Integration tests: Available in benchmark module

### Code Quality

- Java: Google Style formatting (enforced by Spotless plugin)
- Frontend: ESLint + Prettier
- All code must pass formatting checks before commit

## API Documentation

- Swagger UI: `http://localhost:9080/swagger-ui.html`
- Knife4j enhanced docs: `http://localhost:9080/doc.html`
- API endpoints: `/api/chat/**` and `/api/semantic/**`

## Plugin System

The chat plugin system allows extending functionality through Java SPI. Plugins are configured in the application YAML and automatically discovered by the plugin manager.

## Vector Storage

Supports multiple vector databases for semantic search:
- Chroma (default)
- Milvus
- OpenSearch
- pgvector (PostgreSQL extension)

## Common Tasks

### Adding New LLM Provider

1. Implement LangChain4J provider interface in `chat/server/llm/`
2. Add configuration properties in `application.yaml`
3. Register provider in LLM factory

### Adding New Database Support

1. Add database-specific dialect in `headless/core/src/main/java/com/tencent/supersonic/headless/core/translator/`
2. Add configuration in `application-{database}.yaml`
3. Update database initialization scripts in `launchers/standalone/src/main/resources/db/`

### Extending Chat Plugins

1. Create plugin class implementing ChatPlugin interface
2. Add plugin configuration in `application.yaml`
3. Plugin will be auto-discovered via component scanning