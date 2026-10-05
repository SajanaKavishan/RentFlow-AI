using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddTenantMaintenanceRequestExperience : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "PreferredAccessWindow",
                table: "MaintenanceRequests",
                type: "character varying(16)",
                maxLength: 16,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ReferenceCode",
                table: "MaintenanceRequests",
                type: "character varying(19)",
                maxLength: 19,
                nullable: false,
                computedColumnSql: "'MR-' || upper(substr(md5(\"Id\"::text), 1, 16))",
                stored: true);

            migrationBuilder.CreateIndex(
                name: "IX_MaintenanceRequests_ReferenceCode",
                table: "MaintenanceRequests",
                column: "ReferenceCode",
                unique: true);

            migrationBuilder.AddCheckConstraint(
                name: "CK_MaintenanceRequest_PreferredAccessWindow",
                table: "MaintenanceRequests",
                sql: "\"PreferredAccessWindow\" IS NULL OR \"PreferredAccessWindow\" IN ('Morning', 'Afternoon', 'Evening')");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_MaintenanceRequests_ReferenceCode",
                table: "MaintenanceRequests");

            migrationBuilder.DropCheckConstraint(
                name: "CK_MaintenanceRequest_PreferredAccessWindow",
                table: "MaintenanceRequests");

            migrationBuilder.DropColumn(
                name: "ReferenceCode",
                table: "MaintenanceRequests");

            migrationBuilder.DropColumn(
                name: "PreferredAccessWindow",
                table: "MaintenanceRequests");
        }
    }
}
