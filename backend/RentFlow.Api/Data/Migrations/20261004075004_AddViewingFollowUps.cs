using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddViewingFollowUps : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ViewingFollowUps",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ViewingId = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    ClaimedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    Decision = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: true),
                    RespondedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ViewingFollowUps", x => x.Id);
                    table.CheckConstraint("CK_ViewingFollowUp_Response", "(\"Decision\" IS NULL AND \"RespondedAt\" IS NULL) OR (\"Decision\" IS NOT NULL AND \"Decision\" IN ('ApplyNow','NotNow') AND \"RespondedAt\" IS NOT NULL)");
                    table.ForeignKey(
                        name: "FK_ViewingFollowUps_Users_TenantId",
                        column: x => x.TenantId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ViewingFollowUps_ViewingRequests_ViewingId",
                        column: x => x.ViewingId,
                        principalTable: "ViewingRequests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ViewingFollowUps_TenantId_ClaimedAt",
                table: "ViewingFollowUps",
                columns: new[] { "TenantId", "ClaimedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_ViewingFollowUps_ViewingId",
                table: "ViewingFollowUps",
                column: "ViewingId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ViewingFollowUps");
        }
    }
}
