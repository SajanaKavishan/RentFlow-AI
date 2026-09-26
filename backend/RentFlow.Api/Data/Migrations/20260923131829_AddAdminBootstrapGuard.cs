using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAdminBootstrapGuard : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "AdminBootstrapRecords",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false),
                    AdminUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AdminBootstrapRecords", x => x.Id);
                    table.CheckConstraint("CK_AdminBootstrapRecords_Singleton", "\"Id\" = 1");
                    table.ForeignKey(
                        name: "FK_AdminBootstrapRecords_Users_AdminUserId",
                        column: x => x.AdminUserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AdminBootstrapRecords_AdminUserId",
                table: "AdminBootstrapRecords",
                column: "AdminUserId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AdminBootstrapRecords");
        }
    }
}
