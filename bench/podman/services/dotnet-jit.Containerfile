# .NET JIT (R2R) microservice — build + publish in container
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS builder
RUN apt-get update && apt-get install -y --no-install-recommends pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY implementations/dotnet-minimal/microservice/microservice.csproj ./
RUN dotnet restore
COPY implementations/dotnet-minimal/microservice/ ./
RUN dotnet publish -c Release -o /publish

FROM mcr.microsoft.com/dotnet/aspnet:10.0
RUN apt-get update && apt-get install -y --no-install-recommends libgssapi-krb5-2 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /publish ./
EXPOSE 3003
ENV PORT=3003
ENV DOTNET_EnableHWIntrinsic=0
ENV DOTNET_EnableARM64JittedIntrinsics=0
ENV DOTNET_TieredCompilation=0
ENV DOTNET_TC_QuickJitForLoops=1
ENV DOTNET_GCName=libclrgc.so
ENTRYPOINT ["dotnet", "/app/microservice.dll"]
