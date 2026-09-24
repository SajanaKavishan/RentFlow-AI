# Local initial Admin provisioning

The initial Admin is created only by an explicit, interactive command. The command is available only when the API host environment is `Development`, creates an active user with the existing `Admin` role, and exits without starting the HTTP server. It never accepts a password as an argument and never prints the account values, password, hash, or a token.

Public registration remains limited to `Tenant` and `Landlord`.

## First-time local setup

Run these commands from the repository root.

1. Configure the local development PostgreSQL connection with user-secrets (or retain an equivalent existing local configuration):

   ```powershell
   dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Host=localhost;Port=5432;Database=rentflow;Username=<local-user>;Password=<local-database-password>" --project backend/RentFlow.Api
   ```

   Configure the API's other required development secrets, including `Jwt:SigningKey` and the existing `CloudflareR2` settings, before starting the web server. Do not put secrets in `appsettings*.json`.

2. Apply the EF Core migrations to the local development database:

   ```powershell
   dotnet ef database update --project backend/RentFlow.Api --startup-project backend/RentFlow.Api
   ```

3. In an interactive terminal, run exactly:

   ```powershell
   dotnet run --project backend/RentFlow.Api -- --bootstrap-admin
   ```

   Enter the requested full name, email, phone number, password, and password confirmation. Password input is not echoed. The password must satisfy the existing policy: at least eight characters with an uppercase letter, lowercase letter, number, and non-alphanumeric character.

   A successful run prints only `Initial Admin account created successfully.` and exits. A second run is refused. If an Admin already exists, the command also refuses and does not modify that account.

4. Start the API normally:

   ```powershell
   dotnet run --project backend/RentFlow.Api
   ```

5. In another terminal, start the existing web application:

   ```powershell
   cd web/rentflow-web
   npm install
   npm run dev
   ```

6. Open `http://localhost:5173/login` and sign in with the email and password entered at the bootstrap prompts. The web app's default API URL is `http://localhost:5277`.

## How one-time provisioning is enforced

Migration `AddAdminBootstrapGuard` creates `AdminBootstrapRecords`. Its primary key and `Id = 1` check constraint permit only the singleton bootstrap record. The Admin user and that record are written in one database transaction. The normalized-email unique index continues to protect email ownership. Consequently, concurrent bootstrap processes cannot both commit, and a failed transaction does not leave a partial Admin or consume the one-time marker.

## Authorized local recovery

There is no public, automatic, or normally enabled recovery path. Recovery is a deliberate database-owner operation for the local **Development database only**.

If the initial Admin becomes inaccessible:

1. Stop the API and web app. Confirm the connection points to the intended local development database with `SELECT current_database();`; never use this procedure against staging or production.
2. Back up the database.
3. As the authorized local database owner, inspect the exact bootstrap record and linked Admin before changing anything:

   ```sql
   SELECT b."Id", b."AdminUserId", b."CompletedAt", u."Email", u."Role", u."IsActive"
   FROM "AdminBootstrapRecords" AS b
   JOIN "Users" AS u ON u."Id" = b."AdminUserId"
   WHERE b."Id" = 1;
   ```

4. After verifying the returned user ID, remove only that bootstrap record and its linked local Admin in a transaction, substituting the verified UUID literally:

   ```sql
   BEGIN;
   DELETE FROM "AdminBootstrapRecords"
   WHERE "Id" = 1 AND "AdminUserId" = '<verified-admin-user-id>';
   DELETE FROM "Users"
   WHERE "Id" = '<verified-admin-user-id>' AND "Role" = 'Admin';
   ```

   Check that each `DELETE` affected exactly one row. If both did, issue `COMMIT`; otherwise issue `ROLLBACK` and investigate. Foreign-key references will prevent unsafe deletion rather than cascade it.

5. Rerun the interactive bootstrap command and then verify normal login.

This recovery intentionally requires direct, authorized database access and service downtime. It does not overwrite an existing user or bypass authentication.
