using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddRentScheduleItems : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "RentScheduleItems",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    LeaseAgreementId = table.Column<Guid>(type: "uuid", nullable: false),
                    DueDate = table.Column<DateOnly>(type: "date", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RentScheduleItems", x => x.Id);
                    table.ForeignKey(
                        name: "FK_RentScheduleItems_LeaseAgreements_LeaseAgreementId",
                        column: x => x.LeaseAgreementId,
                        principalTable: "LeaseAgreements",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_RentScheduleItems_DueDate",
                table: "RentScheduleItems",
                column: "DueDate");

            migrationBuilder.CreateIndex(
                name: "IX_RentScheduleItems_LeaseAgreementId",
                table: "RentScheduleItems",
                column: "LeaseAgreementId");

            migrationBuilder.CreateIndex(
                name: "IX_RentScheduleItems_LeaseAgreementId_DueDate",
                table: "RentScheduleItems",
                columns: new[] { "LeaseAgreementId", "DueDate" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_RentScheduleItems_Status",
                table: "RentScheduleItems",
                column: "Status");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "RentScheduleItems");
        }
    }
}
