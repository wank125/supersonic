# Stage 1: Build backend + frontend
FROM eclipse-temurin:21-jdk AS builder

ARG SUPERSONIC_VERSION=1.0.0-SNAPSHOT
ENV MAVEN_VERSION=3.9.9
ENV NODE_MAJOR=20

WORKDIR /build

# Install build dependencies: Maven, Node.js, pnpm, zip
RUN apt-get update && apt-get install -y curl unzip zip && \
    # Install Maven
    curl -fsSL https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz | tar xz -C /opt && \
    ln -s /opt/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/local/bin/mvn && \
    # Install Node.js
    curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get install -y nodejs && \
    # Install pnpm
    npm install -g pnpm && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY . .

# Build backend (all modules)
RUN mvn clean package -DskipTests -Dspotless.skip=true

# Build frontend
RUN chmod +x webapp/start-fe-prod.sh && \
    cd webapp && sh ./start-fe-prod.sh

# Copy build artifacts to assembly/build for packaging
RUN cp webapp/supersonic-webapp.tar.gz assembly/build/ && \
    cp launchers/standalone/target/*.tar.gz assembly/build/

# Package release
RUN cd assembly/build && \
    RELEASE_DIR=supersonic-standalone-${SUPERSONIC_VERSION} && \
    SERVICE_NAME=launchers-standalone-${SUPERSONIC_VERSION} && \
    rm -rf "$RELEASE_DIR" "${RELEASE_DIR}.zip" 2>/dev/null; \
    mkdir -p $RELEASE_DIR && \
    tar xf supersonic-webapp.tar.gz && \
    mv supersonic-webapp $RELEASE_DIR/webapp && \
    echo '{"env": ""}' > $RELEASE_DIR/webapp/supersonic.config.json && \
    tar xf ${SERVICE_NAME}-bin.tar.gz && \
    cp -r ${SERVICE_NAME}/* $RELEASE_DIR/ && \
    zip -r ${RELEASE_DIR}.zip $RELEASE_DIR

# Stage 2: Runtime with JRE only
FROM eclipse-temurin:21-jre

ARG SUPERSONIC_VERSION=1.0.0-SNAPSHOT

WORKDIR /usr/src/app

COPY --from=builder /build/assembly/build/supersonic-standalone-${SUPERSONIC_VERSION}.zip .

RUN apt-get update && apt-get install -y unzip && \
    unzip supersonic-standalone-${SUPERSONIC_VERSION}.zip && \
    rm supersonic-standalone-${SUPERSONIC_VERSION}.zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/src/app/supersonic-standalone-${SUPERSONIC_VERSION} /usr/src/app/supersonic-standalone-latest

WORKDIR /usr/src/app/supersonic-standalone-${SUPERSONIC_VERSION}

EXPOSE 9080

RUN chmod +x bin/supersonic-daemon.sh
CMD ["bash", "-c", "bin/supersonic-daemon.sh restart standalone ${S2_DB_TYPE} && tail -f /dev/null"]
