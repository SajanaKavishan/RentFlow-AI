using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddViewingReviews : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ViewingReviews",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ViewingId = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    PropertyId = table.Column<Guid>(type: "uuid", nullable: false),
                    LandlordId = table.Column<Guid>(type: "uuid", nullable: false),
                    PropertyRating = table.Column<int>(type: "integer", nullable: false),
                    LandlordRating = table.Column<int>(type: "integer", nullable: false),
                    Comment = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ViewingReviews", x => x.Id);
                    table.CheckConstraint("CK_ViewingReview_Ratings", "\"PropertyRating\" BETWEEN 1 AND 5 AND \"LandlordRating\" BETWEEN 1 AND 5");
                    table.ForeignKey(
                        name: "FK_ViewingReviews_Properties_PropertyId",
                        column: x => x.PropertyId,
                        principalTable: "Properties",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ViewingReviews_Users_LandlordId",
                        column: x => x.LandlordId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_ViewingReviews_Users_TenantId",
                        column: x => x.TenantId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ViewingReviews_ViewingRequests_ViewingId",
                        column: x => x.ViewingId,
                        principalTable: "ViewingRequests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ViewingReviews_LandlordId_CreatedAt",
                table: "ViewingReviews",
                columns: new[] { "LandlordId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_ViewingReviews_PropertyId_CreatedAt",
                table: "ViewingReviews",
                columns: new[] { "PropertyId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_ViewingReviews_TenantId",
                table: "ViewingReviews",
                column: "TenantId");

            migrationBuilder.CreateIndex(
                name: "IX_ViewingReviews_ViewingId",
                table: "ViewingReviews",
                column: "ViewingId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ViewingReviews");
        }
    }
}
