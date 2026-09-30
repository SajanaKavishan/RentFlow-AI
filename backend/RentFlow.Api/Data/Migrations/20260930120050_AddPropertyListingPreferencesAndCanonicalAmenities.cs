using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPropertyListingPreferencesAndCanonicalAmenities : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "CanonicalKey",
                table: "PropertyAmenities",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "AdvertisedSecurityDeposit",
                table: "Properties",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: true);

            migrationBuilder.AddColumn<string[]>(
                name: "IncludedUtilities",
                table: "Properties",
                type: "text[]",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PetPolicy",
                table: "Properties",
                type: "character varying(32)",
                maxLength: 32,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PetPolicyNotes",
                table: "Properties",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "PreferredLeaseTermMonths",
                table: "Properties",
                type: "integer",
                nullable: true);

            // Preserve every legacy display name. Only the first occurrence of
            // a high-confidence alias per property is assigned a canonical key;
            // duplicate aliases and unknown/custom values deliberately remain null.
            migrationBuilder.Sql(
                """
                WITH candidates AS (
                    SELECT "Id", "PropertyId",
                        CASE
                            WHEN lower(trim("Name")) IN ('wifi', 'wi-fi', 'wi fi', 'wireless internet') THEN 'wifi'
                            WHEN lower(trim("Name")) IN ('parking', 'car parking') THEN 'parking'
                            WHEN lower(trim("Name")) IN ('a/c', 'ac', 'air conditioning', 'air-conditioning', 'air conditioner') THEN 'air-conditioning'
                            WHEN lower(trim("Name")) IN ('washer dryer', 'washer / dryer', 'washer-dryer', 'washer and dryer', 'laundry') THEN 'washer-dryer'
                            WHEN lower(trim("Name")) IN ('gym', 'fitness centre', 'fitness center') THEN 'gym'
                            WHEN lower(trim("Name")) IN ('pool', 'swimming pool', 'swimming-pool') THEN 'swimming-pool'
                            WHEN lower(trim("Name")) = 'balcony' THEN 'balcony'
                            WHEN lower(trim("Name")) IN ('elevator', 'lift') THEN 'elevator'
                            WHEN lower(trim("Name")) = 'furnished' THEN 'furnished'
                            WHEN lower(trim("Name")) = 'garden' THEN 'garden'
                            WHEN lower(trim("Name")) IN ('security', 'security service') THEN 'security'
                            WHEN lower(trim("Name")) IN ('rooftop', 'roof terrace') THEN 'rooftop'
                        END AS canonical_key
                    FROM "PropertyAmenities"
                ), ranked AS (
                    SELECT "Id", canonical_key,
                        row_number() OVER (PARTITION BY "PropertyId", canonical_key ORDER BY "Id") AS occurrence
                    FROM candidates
                    WHERE canonical_key IS NOT NULL
                )
                UPDATE "PropertyAmenities" AS amenity
                SET "CanonicalKey" = ranked.canonical_key
                FROM ranked
                WHERE amenity."Id" = ranked."Id" AND ranked.occurrence = 1;
                """);

            migrationBuilder.CreateIndex(
                name: "IX_PropertyAmenities_PropertyId_CanonicalKey",
                table: "PropertyAmenities",
                columns: new[] { "PropertyId", "CanonicalKey" },
                unique: true,
                filter: "\"CanonicalKey\" IS NOT NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_PropertyAmenities_PropertyId_CanonicalKey",
                table: "PropertyAmenities");

            migrationBuilder.DropColumn(
                name: "CanonicalKey",
                table: "PropertyAmenities");

            migrationBuilder.DropColumn(
                name: "AdvertisedSecurityDeposit",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "IncludedUtilities",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "PetPolicy",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "PetPolicyNotes",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "PreferredLeaseTermMonths",
                table: "Properties");
        }
    }
}
