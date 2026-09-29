using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class StrengthenPropertyListingContract : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "IsPrimary",
                table: "PropertyImages",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<int>(
                name: "SortOrder",
                table: "PropertyImages",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "AreaType",
                table: "Properties",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<DateOnly>(
                name: "AvailableFrom",
                table: "Properties",
                type: "date",
                nullable: true);

            migrationBuilder.Sql(
                """
                WITH ranked AS (
                    SELECT "Id",
                           ROW_NUMBER() OVER (
                               PARTITION BY "PropertyId"
                               ORDER BY "UploadedAt", "Id") - 1 AS "Position"
                    FROM "PropertyImages"
                )
                UPDATE "PropertyImages" AS images
                SET "SortOrder" = ranked."Position"::integer
                FROM ranked
                WHERE images."Id" = ranked."Id";

                WITH ranked AS (
                    SELECT "Id",
                           ROW_NUMBER() OVER (
                               PARTITION BY "PropertyId"
                               ORDER BY "SortOrder", "UploadedAt", "Id") AS "Position"
                    FROM "PropertyImages"
                )
                UPDATE "PropertyImages" AS images
                SET "IsPrimary" = TRUE
                FROM ranked
                WHERE images."Id" = ranked."Id"
                  AND ranked."Position" = 1;
                """);

            migrationBuilder.CreateIndex(
                name: "IX_PropertyImages_PropertyId_IsPrimary",
                table: "PropertyImages",
                columns: new[] { "PropertyId", "IsPrimary" },
                unique: true,
                filter: "\"IsPrimary\" = TRUE");

            migrationBuilder.CreateIndex(
                name: "IX_PropertyImages_PropertyId_SortOrder",
                table: "PropertyImages",
                columns: new[] { "PropertyId", "SortOrder" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_PropertyImages_PropertyId_IsPrimary",
                table: "PropertyImages");

            migrationBuilder.DropIndex(
                name: "IX_PropertyImages_PropertyId_SortOrder",
                table: "PropertyImages");

            migrationBuilder.DropColumn(
                name: "IsPrimary",
                table: "PropertyImages");

            migrationBuilder.DropColumn(
                name: "SortOrder",
                table: "PropertyImages");

            migrationBuilder.DropColumn(
                name: "AreaType",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "AvailableFrom",
                table: "Properties");
        }
    }
}
