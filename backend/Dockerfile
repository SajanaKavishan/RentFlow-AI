FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project file and restore dependencies
COPY RentFlow.Api/RentFlow.Api.csproj RentFlow.Api/
RUN dotnet restore RentFlow.Api/RentFlow.Api.csproj

# Copy source code and publish release build
COPY RentFlow.Api/ RentFlow.Api/
WORKDIR /src/RentFlow.Api
RUN dotnet publish RentFlow.Api.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8080 \
    DOTNET_RUNNING_IN_CONTAINER=true

EXPOSE 8080

COPY --from=build /app/publish .

# Run under the default non-root user built into .NET 8 images
USER $APP_UID

ENTRYPOINT ["dotnet", "RentFlow.Api.dll"]
