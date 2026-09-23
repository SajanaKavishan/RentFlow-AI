using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPropertyReferencesToComponent3 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddForeignKey(
                name: "FK_LeaseAgreements_Properties_PropertyId",
                table: "LeaseAgreements",
                column: "PropertyId",
                principalTable: "Properties",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_RentalOffers_Properties_PropertyId",
                table: "RentalOffers",
                column: "PropertyId",
                principalTable: "Properties",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_LeaseAgreements_Properties_PropertyId",
                table: "LeaseAgreements");

            migrationBuilder.DropForeignKey(
                name: "FK_RentalOffers_Properties_PropertyId",
                table: "RentalOffers");
        }
    }
}
