# THRØ API — one image (ADR-011). Built from the repository root because the API's Gradle build
# includes the packages beside it as composite builds.
#
#   docker build -t thro-api .
#   docker run --rm -p 8080:8080 -e PGHOST=host.docker.internal -e THRO_DEV_AUTH=1 thro-api
#
# The image runs the HTTP server. The same image runs the migration step:
#   docker run --rm -e PGHOST=... -e PGUSER=thro_owner ... thro-api migrate

FROM gradle:9-jdk21 AS build
WORKDIR /src
COPY packages ./packages
COPY services/api ./services/api
RUN gradle -p services/api installDist --no-daemon -q

FROM eclipse-temurin:21-jre
RUN useradd --system --home /app thro
WORKDIR /app
COPY --from=build /src/services/api/build/install/thro-api/lib ./lib
COPY --from=build /src/services/api/migrations ./services/api/migrations
COPY services/api/docker-entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh && chown -R thro /app
USER thro
EXPOSE 8080
ENV PORT=8080
ENTRYPOINT ["./entrypoint.sh"]
CMD ["serve"]
