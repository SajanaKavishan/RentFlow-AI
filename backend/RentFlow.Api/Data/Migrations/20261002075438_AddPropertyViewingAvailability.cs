using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPropertyViewingAvailability : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "DurationMinutes",
                table: "ViewingRequests",
                type: "integer",
                nullable: false,
                defaultValue: 60);

            migrationBuilder.AddColumn<int>(
                name: "ViewingSlotDurationMinutes",
                table: "Properties",
                type: "integer",
                nullable: false,
                defaultValue: 60);

            migrationBuilder.AddColumn<string>(
                name: "ViewingTimeZoneId",
                table: "Properties",
                type: "character varying(100)",
                maxLength: 100,
                nullable: false,
                defaultValue: "Asia/Colombo");

            migrationBuilder.CreateTable(
                name: "PropertyViewingAvailabilities",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    PropertyId = table.Column<Guid>(type: "uuid", nullable: false),
                    DayOfWeek = table.Column<int>(type: "integer", nullable: false),
                    StartTime = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    EndTime = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    IsEnabled = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PropertyViewingAvailabilities", x => x.Id);
                    table.CheckConstraint("CK_ViewingWindow_Times", "NOT \"IsEnabled\" OR \"StartTime\" < \"EndTime\"");
                    table.CheckConstraint("CK_ViewingWindow_Weekday", "\"DayOfWeek\" BETWEEN 0 AND 6");
                    table.ForeignKey(
                        name: "FK_PropertyViewingAvailabilities_Properties_PropertyId",
                        column: x => x.PropertyId,
                        principalTable: "Properties",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ViewingRequests_PropertyId_Status_RequestedDateTime",
                table: "ViewingRequests",
                columns: new[] { "PropertyId", "Status", "RequestedDateTime" });

            migrationBuilder.CreateIndex(
                name: "IX_ViewingRequests_RequestedDateTime",
                table: "ViewingRequests",
                column: "RequestedDateTime");

            migrationBuilder.CreateIndex(
                name: "IX_ViewingRequests_Status",
                table: "ViewingRequests",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_ViewingRequests_TenantId_PropertyId_RequestedDateTime",
                table: "ViewingRequests",
                columns: new[] { "TenantId", "PropertyId", "RequestedDateTime" });

            migrationBuilder.AddCheckConstraint(
                name: "CK_Viewing_Duration",
                table: "ViewingRequests",
                sql: "\"DurationMinutes\" > 0");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Property_ViewingDuration",
                table: "Properties",
                sql: "\"ViewingSlotDurationMinutes\" IN (30,45,60,90)");

            migrationBuilder.CreateIndex(
                name: "IX_PropertyViewingAvailabilities_PropertyId_DayOfWeek",
                table: "PropertyViewingAvailabilities",
                columns: new[] { "PropertyId", "DayOfWeek" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "PropertyViewingAvailabilities");

            migrationBuilder.DropIndex(
                name: "IX_ViewingRequests_PropertyId_Status_RequestedDateTime",
                table: "ViewingRequests");

            migrationBuilder.DropIndex(
                name: "IX_ViewingRequests_RequestedDateTime",
                table: "ViewingRequests");

            migrationBuilder.DropIndex(
                name: "IX_ViewingRequests_Status",
                table: "ViewingRequests");

            migrationBuilder.DropIndex(
                name: "IX_ViewingRequests_TenantId_PropertyId_RequestedDateTime",
                table: "ViewingRequests");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Viewing_Duration",
                table: "ViewingRequests");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Property_ViewingDuration",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "DurationMinutes",
                table: "ViewingRequests");

            migrationBuilder.DropColumn(
                name: "ViewingSlotDurationMinutes",
                table: "Properties");

            migrationBuilder.DropColumn(
                name: "ViewingTimeZoneId",
                table: "Properties");
        }
    }
}
