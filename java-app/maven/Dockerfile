FROM docker.io/maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /src
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q clean package -DskipTests

FROM gcr.io/distroless/java21-debian12:nonroot
ARG GIT_SHA=unknown
ENV APP_VERSION=${GIT_SHA}
COPY --from=builder /src/target/svc-__SVC__.jar /app.jar
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app.jar"]
