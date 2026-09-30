# RentFlow-AI
An Agentic AI-powered property rental and management platform integrating React, Flutter, ASP.NET Core Web API, and PostgreSQL for SE3090.

## Continuous integration

The GitHub Actions workflow runs on pushes and pull requests targeting `dev` or
`main`. It validates the ASP.NET Core backend against a disposable PostgreSQL 16
service, lints/tests/builds the React application, runs the Python Agent tests,
and analyzes/tests the Flutter application. The workflow is CI only and does not
deploy any component.

The backend job sets `RENTFLOW_TEST_POSTGRES_CONNECTION_STRING` to its isolated
CI database so the PostgreSQL migration and constraint tests execute instead of
being skipped. Test reports for the backend, React application, Python Agent, and
Flutter application are retained as workflow artifacts for 14 days.

Run equivalent checks locally from the repository root:

```powershell
dotnet restore backend/RentFlow.Api.Tests/RentFlow.Api.Tests.csproj
dotnet build backend/RentFlow.Api/RentFlow.Api.csproj --configuration Release --no-restore
dotnet test backend/RentFlow.Api.Tests/RentFlow.Api.Tests.csproj --configuration Release --no-restore

Set-Location web/rentflow-web
npm.cmd ci
npm.cmd run lint
npm.cmd run test
npm.cmd run build

Set-Location ../../agent
python -m pip install --requirement requirements.txt
python -m pytest

Set-Location ../mobile/rentflow_mobile
flutter pub get
flutter analyze
flutter test
```

To include the PostgreSQL-specific backend tests locally, set
`RENTFLOW_TEST_POSTGRES_CONNECTION_STRING` to a disposable PostgreSQL database
whose name begins with `rentflow_component3_test`. Never point these tests at a
development or production database.
