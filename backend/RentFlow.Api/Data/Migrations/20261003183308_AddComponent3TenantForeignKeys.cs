using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddComponent3TenantForeignKeys : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddForeignKey(
                name: "FK_LeaseAgreements_Users_TenantId",
                table: "LeaseAgreements",
                column: "TenantId",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_Payments_Users_TenantId",
                table: "Payments",
                column: "TenantId",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_RentalOffers_Users_TenantId",
                table: "RentalOffers",
                column: "TenantId",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_LeaseAgreements_Users_TenantId",
                table: "LeaseAgreements");

            migrationBuilder.DropForeignKey(
                name: "FK_Payments_Users_TenantId",
                table: "Payments");

            migrationBuilder.DropForeignKey(
                name: "FK_RentalOffers_Users_TenantId",
                table: "RentalOffers");
        }
    }
}
