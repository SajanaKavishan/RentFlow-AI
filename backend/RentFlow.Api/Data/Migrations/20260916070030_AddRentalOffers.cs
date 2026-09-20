using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddRentalOffers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "RentalOffers",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    RentalApplicationId = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    PropertyId = table.Column<Guid>(type: "uuid", nullable: false),
                    MonthlyRent = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    SecurityDeposit = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    ProposedStartDate = table.Column<DateOnly>(type: "date", nullable: false),
                    ProposedEndDate = table.Column<DateOnly>(type: "date", nullable: false),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    LandlordNote = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RentalOffers", x => x.Id);
                    table.ForeignKey(
                        name: "FK_RentalOffers_RentalApplications_RentalApplicationId",
                        column: x => x.RentalApplicationId,
                        principalTable: "RentalApplications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_RentalOffers_PropertyId",
                table: "RentalOffers",
                column: "PropertyId");

            migrationBuilder.CreateIndex(
                name: "IX_RentalOffers_RentalApplicationId",
                table: "RentalOffers",
                column: "RentalApplicationId");

            migrationBuilder.CreateIndex(
                name: "IX_RentalOffers_Status",
                table: "RentalOffers",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_RentalOffers_TenantId",
                table: "RentalOffers",
                column: "TenantId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "RentalOffers");
        }
    }
}
