# .NET Native AOT microservice — compile to native binary in container
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS builder
RUN apt-get update && apt-get install -y --no-install-recommends clang zlib1g-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY implementations/dotnet-aot/microservice/microservice.csproj ./
RUN dotnet restore
COPY implementations/dotnet-aot/microservice/ ./
RUN dotnet publish -c Release -o /publish && strip /publish/microservice

FROM mcr.microsoft.com/dotnet/runtime-deps:10.0
RUN apt-get update && apt-get install -y --no-install-recommends libgssapi-krb5-2 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /publish ./
EXPOSE 3004
ENV PORT=3004
ENTRYPOINT ["/app/microservice"]
