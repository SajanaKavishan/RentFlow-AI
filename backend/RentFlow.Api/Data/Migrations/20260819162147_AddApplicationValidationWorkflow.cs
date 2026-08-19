using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddApplicationValidationWorkflow : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ApplicationValidationWorkflows",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ApplicationId = table.Column<Guid>(type: "uuid", nullable: false),
                    Objective = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    CurrentStep = table.Column<int>(type: "integer", nullable: false),
                    CompletenessScore = table.Column<decimal>(type: "numeric(5,2)", precision: 5, scale: 2, nullable: true),
                    Recommendation = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    RequiresHumanApproval = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ApplicationValidationWorkflows", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ApplicationValidationWorkflows_RentalApplications_Applicati~",
                        column: x => x.ApplicationId,
                        principalTable: "RentalApplications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "ApplicationValidationSteps",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    WorkflowId = table.Column<Guid>(type: "uuid", nullable: false),
                    AgentName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    StepOrder = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    InputSummary = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    ResultJson = table.Column<string>(type: "text", nullable: true),
                    ErrorMessage = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    StartedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ApplicationValidationSteps", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ApplicationValidationSteps_ApplicationValidationWorkflows_W~",
                        column: x => x.WorkflowId,
                        principalTable: "ApplicationValidationWorkflows",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ApplicationValidationSteps_WorkflowId_StepOrder",
                table: "ApplicationValidationSteps",
                columns: new[] { "WorkflowId", "StepOrder" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ApplicationValidationWorkflows_ApplicationId",
                table: "ApplicationValidationWorkflows",
                column: "ApplicationId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ApplicationValidationSteps");

            migrationBuilder.DropTable(
                name: "ApplicationValidationWorkflows");
        }
    }
}
