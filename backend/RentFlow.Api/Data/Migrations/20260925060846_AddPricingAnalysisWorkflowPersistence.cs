using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RentFlow.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPricingAnalysisWorkflowPersistence : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "PricingAnalysisWorkflows",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    PropertyId = table.Column<Guid>(type: "uuid", nullable: false),
                    Objective = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    CurrentStep = table.Column<int>(type: "integer", nullable: false),
                    EvidencePolicyVersion = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    EvidenceSufficiency = table.Column<int>(type: "integer", nullable: true),
                    Confidence = table.Column<int>(type: "integer", nullable: true),
                    AgentVersion = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ResultJson = table.Column<string>(type: "text", nullable: true),
                    ErrorMessage = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    StartedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PricingAnalysisWorkflows", x => x.Id);
                    table.CheckConstraint("CK_PricingAnalysisWorkflows_CurrentStep", "\"CurrentStep\" >= 0 AND \"CurrentStep\" <= 6");
                    table.ForeignKey(
                        name: "FK_PricingAnalysisWorkflows_Properties_PropertyId",
                        column: x => x.PropertyId,
                        principalTable: "Properties",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "PricingAnalysisWorkflowSteps",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    WorkflowId = table.Column<Guid>(type: "uuid", nullable: false),
                    StepName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    StepOrder = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    OutputSummary = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    ResultJson = table.Column<string>(type: "text", nullable: true),
                    ValidationSummary = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    ErrorMessage = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                    StartedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PricingAnalysisWorkflowSteps", x => x.Id);
                    table.CheckConstraint("CK_PricingAnalysisWorkflowSteps_StepOrder", "\"StepOrder\" >= 1 AND \"StepOrder\" <= 6");
                    table.ForeignKey(
                        name: "FK_PricingAnalysisWorkflowSteps_PricingAnalysisWorkflows_Workf~",
                        column: x => x.WorkflowId,
                        principalTable: "PricingAnalysisWorkflows",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_PricingAnalysisWorkflows_PropertyId",
                table: "PricingAnalysisWorkflows",
                column: "PropertyId");

            migrationBuilder.CreateIndex(
                name: "IX_PricingAnalysisWorkflowSteps_WorkflowId_StepOrder",
                table: "PricingAnalysisWorkflowSteps",
                columns: new[] { "WorkflowId", "StepOrder" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "PricingAnalysisWorkflowSteps");

            migrationBuilder.DropTable(
                name: "PricingAnalysisWorkflows");
        }
    }
}
