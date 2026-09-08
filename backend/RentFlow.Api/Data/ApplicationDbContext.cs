using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Models;

namespace RentFlow.Api.Data;

public class ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : DbContext(options)
{
    public DbSet<ApplicationUser> Users => Set<ApplicationUser>();

    public DbSet<ViewingRequest> ViewingRequests => Set<ViewingRequest>();

    public DbSet<RentalApplication> RentalApplications => Set<RentalApplication>();

    public DbSet<ApplicationDocument> ApplicationDocuments => Set<ApplicationDocument>();

    public DbSet<ApplicationValidationWorkflow> ApplicationValidationWorkflows => Set<ApplicationValidationWorkflow>();

    public DbSet<ApplicationValidationStep> ApplicationValidationSteps => Set<ApplicationValidationStep>();

    public DbSet<MaintenanceRequest> MaintenanceRequests => Set<MaintenanceRequest>();

    public DbSet<MaintenanceStatusHistory> MaintenanceStatusHistories => Set<MaintenanceStatusHistory>();

    public DbSet<RepairEstimate> RepairEstimates => Set<RepairEstimate>();

    public DbSet<MaintenanceAttachment> MaintenanceAttachments => Set<MaintenanceAttachment>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<ApplicationUser>(entity =>
        {
            entity.HasKey(user => user.Id);

            entity.Property(user => user.FullName)
                .HasMaxLength(200)
                .IsRequired();

            entity.Property(user => user.Email)
                .HasMaxLength(320)
                .IsRequired();

            entity.Property(user => user.NormalizedEmail)
                .HasMaxLength(320)
                .IsRequired();

            entity.Property(user => user.PhoneNumber)
                .HasMaxLength(32)
                .IsRequired();

            entity.Property(user => user.PasswordHash)
                .HasMaxLength(512)
                .IsRequired();

            entity.Property(user => user.Role)
                .HasConversion<string>()
                .HasMaxLength(32)
                .IsRequired();

            entity.Property(user => user.IsActive)
                .IsRequired();

            entity.Property(user => user.CreatedAt)
                .IsRequired();

            entity.Property(user => user.UpdatedAt)
                .IsRequired();

            entity.HasIndex(user => user.NormalizedEmail)
                .IsUnique();
        });

        modelBuilder.Entity<ViewingRequest>(entity =>
        {
            entity.HasKey(viewing => viewing.Id);

            entity.Property(viewing => viewing.TenantId)
                .IsRequired();

            entity.Property(viewing => viewing.PropertyId)
                .IsRequired();

            entity.Property(viewing => viewing.RequestedDateTime)
                .IsRequired();

            entity.Property(viewing => viewing.Status)
                .IsRequired();

            entity.Property(viewing => viewing.TenantMessage)
                .HasMaxLength(1000);

            entity.Property(viewing => viewing.LandlordResponse)
                .HasMaxLength(1000);

            entity.Property(viewing => viewing.CreatedAt)
                .IsRequired();

            entity.Property(viewing => viewing.UpdatedAt)
                .IsRequired(false);
        });

        modelBuilder.Entity<RentalApplication>(entity =>
        {
            entity.HasKey(application => application.Id);

            entity.Property(application => application.TenantId)
                .IsRequired();

            entity.Property(application => application.PropertyId)
                .IsRequired();

            entity.Property(application => application.MoveInDate)
                .IsRequired();

            entity.Property(application => application.MonthlyIncome)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(application => application.Occupation)
                .HasMaxLength(200)
                .IsRequired();

            entity.Property(application => application.NumberOfOccupants)
                .IsRequired();

            entity.Property(application => application.TenantNote)
                .HasMaxLength(1000)
                .IsRequired(false);

            entity.Property(application => application.Status)
                .IsRequired();

            entity.Property(application => application.LandlordResponse)
                .HasMaxLength(1000)
                .IsRequired(false);

            entity.Property(application => application.CreatedAt)
                .IsRequired();

            entity.Property(application => application.SubmittedAt)
                .IsRequired(false);

            entity.Property(application => application.UpdatedAt)
                .IsRequired(false);

            entity.HasIndex(application => application.TenantId);
            entity.HasIndex(application => application.PropertyId);
            entity.HasIndex(application => application.Status);
        });

        modelBuilder.Entity<ApplicationDocument>(entity =>
        {
            entity.HasKey(document => document.Id);

            entity.Property(document => document.ApplicationId)
                .IsRequired();

            entity.Property(document => document.DocumentType)
                .IsRequired();

            entity.Property(document => document.OriginalFileName)
                .HasMaxLength(255)
                .IsRequired();

            entity.Property(document => document.StorageKey)
                .HasMaxLength(512)
                .IsRequired();

            entity.Property(document => document.ContentType)
                .HasMaxLength(255)
                .IsRequired();

            entity.Property(document => document.FileSizeBytes)
                .IsRequired();

            entity.Property(document => document.UploadedAt)
                .IsRequired();

            entity.HasOne<RentalApplication>()
                .WithMany()
                .HasForeignKey(document => document.ApplicationId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(document => document.ApplicationId);
            entity.HasIndex(document => document.DocumentType);
        });

        modelBuilder.Entity<ApplicationValidationWorkflow>(entity =>
        {
            entity.HasKey(workflow => workflow.Id);

            entity.Property(workflow => workflow.ApplicationId)
                .IsRequired();

            entity.Property(workflow => workflow.Objective)
                .HasMaxLength(2000)
                .IsRequired();

            entity.Property(workflow => workflow.Status)
                .IsRequired();

            entity.Property(workflow => workflow.CurrentStep)
                .IsRequired();

            entity.Property(workflow => workflow.CompletenessScore)
                .HasPrecision(5, 2)
                .IsRequired(false);

            entity.Property(workflow => workflow.Recommendation)
                .HasMaxLength(4000)
                .IsRequired(false);

            entity.Property(workflow => workflow.RequiresHumanApproval)
                .IsRequired();

            entity.Property(workflow => workflow.CreatedAt)
                .IsRequired();

            entity.Property(workflow => workflow.UpdatedAt)
                .IsRequired();

            entity.HasOne(workflow => workflow.Application)
                .WithMany()
                .HasForeignKey(workflow => workflow.ApplicationId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(workflow => workflow.ApplicationId);
        });

        modelBuilder.Entity<ApplicationValidationStep>(entity =>
        {
            entity.HasKey(step => step.Id);

            entity.Property(step => step.WorkflowId)
                .IsRequired();

            entity.Property(step => step.AgentName)
                .HasMaxLength(200)
                .IsRequired();

            entity.Property(step => step.StepOrder)
                .IsRequired();

            entity.Property(step => step.Status)
                .IsRequired();

            entity.Property(step => step.InputSummary)
                .HasMaxLength(4000)
                .IsRequired(false);

            entity.Property(step => step.ResultJson)
                .HasColumnType("text")
                .IsRequired(false);

            entity.Property(step => step.ErrorMessage)
                .HasMaxLength(4000)
                .IsRequired(false);

            entity.Property(step => step.StartedAt)
                .IsRequired(false);

            entity.Property(step => step.CompletedAt)
                .IsRequired(false);

            entity.HasOne(step => step.Workflow)
                .WithMany(workflow => workflow.Steps)
                .HasForeignKey(step => step.WorkflowId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(step => new { step.WorkflowId, step.StepOrder })
                .IsUnique();
        });

        modelBuilder.Entity<MaintenanceRequest>(entity =>
        {
            entity.HasKey(request => request.Id);

            entity.Property(request => request.PropertyId)
                .IsRequired();

            entity.Property(request => request.TenantId)
                .IsRequired();

            entity.Property(request => request.TechnicianId)
                .IsRequired(false);

            entity.Property(request => request.Title)
                .HasMaxLength(200)
                .IsRequired();

            entity.Property(request => request.Description)
                .HasMaxLength(4000)
                .IsRequired();

            entity.Property(request => request.Category)
                .IsRequired();

            entity.Property(request => request.Priority)
                .IsRequired();

            entity.Property(request => request.Status)
                .IsRequired();

            entity.Property(request => request.TenantAccessNotes)
                .HasMaxLength(1000)
                .IsRequired(false);

            entity.Property(request => request.TriageNotes)
                .HasMaxLength(2000)
                .IsRequired(false);

            entity.Property(request => request.AssignmentNotes)
                .HasMaxLength(2000)
                .IsRequired(false);

            entity.Property(request => request.CancellationReason)
                .HasMaxLength(2000)
                .IsRequired(false);

            entity.Property(request => request.CompletedAt)
                .IsRequired(false);

            entity.Property(request => request.CreatedAt)
                .IsRequired();

            entity.Property(request => request.UpdatedAt)
                .IsRequired(false);

            entity.HasIndex(request => request.PropertyId);
            entity.HasIndex(request => request.TenantId);
            entity.HasIndex(request => request.TechnicianId);
            entity.HasIndex(request => request.Status);
            entity.HasIndex(request => new { request.PropertyId, request.Status });
            entity.HasIndex(request => new { request.TenantId, request.CreatedAt });
            entity.HasIndex(request => new { request.TechnicianId, request.Status });
            entity.HasIndex(request => new { request.Priority, request.Status });
        });

        modelBuilder.Entity<MaintenanceStatusHistory>(entity =>
        {
            entity.HasKey(history => history.Id);

            entity.Property(history => history.MaintenanceRequestId)
                .IsRequired();

            entity.Property(history => history.FromStatus)
                .IsRequired(false);

            entity.Property(history => history.ToStatus)
                .IsRequired();

            entity.Property(history => history.ChangedByUserId)
                .IsRequired(false);

            entity.Property(history => history.ChangedAt)
                .IsRequired();

            entity.Property(history => history.Notes)
                .HasMaxLength(2000)
                .IsRequired(false);

            entity.HasOne(history => history.MaintenanceRequest)
                .WithMany()
                .HasForeignKey(history => history.MaintenanceRequestId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(history => history.MaintenanceRequestId);
            entity.HasIndex(history => new { history.MaintenanceRequestId, history.ChangedAt });
        });

        modelBuilder.Entity<RepairEstimate>(entity =>
        {
            entity.HasKey(estimate => estimate.Id);

            entity.Property(estimate => estimate.MaintenanceRequestId)
                .IsRequired();

            entity.Property(estimate => estimate.TechnicianId)
                .IsRequired();

            entity.Property(estimate => estimate.VersionNumber)
                .IsRequired();

            entity.Property(estimate => estimate.LaborCost)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(estimate => estimate.PartsCost)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(estimate => estimate.AdditionalCost)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(estimate => estimate.TotalCost)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(estimate => estimate.Notes)
                .HasMaxLength(4000)
                .IsRequired(false);

            entity.Property(estimate => estimate.Status)
                .IsRequired();

            entity.Property(estimate => estimate.CreatedAt)
                .IsRequired();

            entity.Property(estimate => estimate.UpdatedAt)
                .IsRequired(false);

            entity.Property(estimate => estimate.SubmittedAt)
                .IsRequired(false);

            entity.Property(estimate => estimate.ReviewedAt)
                .IsRequired(false);

            entity.Property(estimate => estimate.ReviewNotes)
                .HasMaxLength(2000)
                .IsRequired(false);

            entity.Property(estimate => estimate.ReviewedByUserId)
                .IsRequired(false);

            entity.HasOne(estimate => estimate.MaintenanceRequest)
                .WithMany()
                .HasForeignKey(estimate => estimate.MaintenanceRequestId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(estimate => estimate.MaintenanceRequestId);
            entity.HasIndex(estimate => new { estimate.MaintenanceRequestId, estimate.CreatedAt });
            entity.HasIndex(estimate => new { estimate.MaintenanceRequestId, estimate.Status });
            entity.HasIndex(estimate => new { estimate.MaintenanceRequestId, estimate.VersionNumber })
                .IsUnique();
        });

        modelBuilder.Entity<MaintenanceAttachment>(entity =>
        {
            entity.HasKey(attachment => attachment.Id);

            entity.Property(attachment => attachment.MaintenanceRequestId).IsRequired();
            entity.Property(attachment => attachment.StorageKey).HasMaxLength(512).IsRequired();
            entity.Property(attachment => attachment.FileName).HasMaxLength(255).IsRequired();
            entity.Property(attachment => attachment.ContentType).HasMaxLength(255).IsRequired();
            entity.Property(attachment => attachment.FileSize).IsRequired();
            entity.Property(attachment => attachment.AttachmentType).HasMaxLength(100).IsRequired(false);
            entity.Property(attachment => attachment.UploadedByUserId).IsRequired();
            entity.Property(attachment => attachment.CreatedAt).IsRequired();

            entity.HasOne<MaintenanceRequest>()
                .WithMany()
                .HasForeignKey(attachment => attachment.MaintenanceRequestId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(attachment => attachment.MaintenanceRequestId);
            entity.HasIndex(attachment => new { attachment.MaintenanceRequestId, attachment.CreatedAt });
            entity.HasIndex(attachment => attachment.UploadedByUserId);
        });
    }
}
