using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddMaintenanceCoordinationWorkflow : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "MaintenanceCoordinationWorkflows",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    MaintenanceRequestId = table.Column<Guid>(type: "uuid", nullable: false),
                    Objective = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    CurrentStep = table.Column<int>(type: "integer", nullable: false),
                    AgentVersion = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    PlanSummary = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    ExecutionSummary = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    FinalResultJson = table.Column<string>(type: "text", nullable: true),
                    ErrorMessage = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    RequiresHumanApproval = table.Column<bool>(type: "boolean", nullable: false),
                    ApprovalStatus = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MaintenanceCoordinationWorkflows", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MaintenanceCoordinationWorkflows_MaintenanceRequests_Mainte~",
                        column: x => x.MaintenanceRequestId,
                        principalTable: "MaintenanceRequests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "MaintenanceCoordinationSteps",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    WorkflowId = table.Column<Guid>(type: "uuid", nullable: false),
                    StepName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    StepOrder = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    InputSummary = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    OutputSummary = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    ValidationSummary = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    ErrorMessage = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    StartedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MaintenanceCoordinationSteps", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MaintenanceCoordinationSteps_MaintenanceCoordinationWorkflo~",
                        column: x => x.WorkflowId,
                        principalTable: "MaintenanceCoordinationWorkflows",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_MaintenanceCoordinationSteps_WorkflowId_StepOrder",
                table: "MaintenanceCoordinationSteps",
                columns: new[] { "WorkflowId", "StepOrder" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_MaintenanceCoordinationWorkflows_MaintenanceRequestId",
                table: "MaintenanceCoordinationWorkflows",
                column: "MaintenanceRequestId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "MaintenanceCoordinationSteps");

            migrationBuilder.DropTable(
                name: "MaintenanceCoordinationWorkflows");
        }
    }
}
