using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Models;

namespace RentFlow.Api.Data;

public class ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
    : DbContext(options)
{
    public DbSet<ApplicationUser> Users => Set<ApplicationUser>();

    public DbSet<AdminBootstrapRecord> AdminBootstrapRecords =>
        Set<AdminBootstrapRecord>();

    public DbSet<Property> Properties => Set<Property>();

    public DbSet<PropertyAmenity> PropertyAmenities => Set<PropertyAmenity>();

    public DbSet<PropertyImage> PropertyImages => Set<PropertyImage>();

    public DbSet<ViewingRequest> ViewingRequests => Set<ViewingRequest>();

    public DbSet<RentalApplication> RentalApplications => Set<RentalApplication>();

    public DbSet<RentalOffer> RentalOffers => Set<RentalOffer>();

    public DbSet<LeaseAgreement> LeaseAgreements => Set<LeaseAgreement>();

    public DbSet<RentScheduleItem> RentScheduleItems => Set<RentScheduleItem>();

    public DbSet<Payment> Payments => Set<Payment>();

    public DbSet<ApplicationDocument> ApplicationDocuments => Set<ApplicationDocument>();

    public DbSet<ApplicationValidationWorkflow> ApplicationValidationWorkflows =>
        Set<ApplicationValidationWorkflow>();

    public DbSet<ApplicationValidationStep> ApplicationValidationSteps =>
        Set<ApplicationValidationStep>();

    public DbSet<Notification> Notifications => Set<Notification>();

    public DbSet<MaintenanceCoordinationWorkflow> MaintenanceCoordinationWorkflows => Set<MaintenanceCoordinationWorkflow>();

    public DbSet<MaintenanceCoordinationStep> MaintenanceCoordinationSteps => Set<MaintenanceCoordinationStep>();

    public DbSet<MaintenanceRequest> MaintenanceRequests => Set<MaintenanceRequest>();

    public DbSet<MaintenanceStatusHistory> MaintenanceStatusHistories => Set<MaintenanceStatusHistory>();

    public DbSet<RepairEstimate> RepairEstimates => Set<RepairEstimate>();

    public DbSet<MaintenanceAttachment> MaintenanceAttachments => Set<MaintenanceAttachment>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // =========================================================
        // USERS
        // =========================================================
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

            entity.HasIndex(user => user.NormalizedEmail)
                .IsUnique();
        });

        modelBuilder.Entity<AdminBootstrapRecord>(entity =>
        {
            entity.HasKey(record => record.Id);

            entity.Property(record => record.Id)
                .ValueGeneratedNever();

            entity.Property(record => record.AdminUserId)
                .IsRequired();

            entity.Property(record => record.CompletedAt)
                .IsRequired();

            entity.ToTable(table => table.HasCheckConstraint(
                "CK_AdminBootstrapRecords_Singleton",
                $"\"Id\" = {AdminBootstrapRecord.SingletonId}"));

            entity.HasOne<ApplicationUser>()
                .WithOne()
                .HasForeignKey<AdminBootstrapRecord>(record => record.AdminUserId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        // =========================================================
        // NOTIFICATIONS
        // =========================================================
        modelBuilder.Entity<Notification>(entity =>
        {
            entity.HasKey(notification => notification.Id);

            entity.Property(notification => notification.RecipientId)
                .IsRequired();

            entity.Property(notification => notification.EventType)
                .HasMaxLength(100)
                .IsRequired();

            entity.Property(notification => notification.RelatedResourceType)
                .HasMaxLength(100)
                .IsRequired();

            entity.Property(notification => notification.RelatedResourceId)
                .IsRequired();

            entity.Property(notification => notification.Title)
                .HasMaxLength(200)
                .IsRequired();

            entity.Property(notification => notification.Message)
                .HasMaxLength(1000)
                .IsRequired();

            entity.Property(notification => notification.CreatedAt)
                .IsRequired();

            entity.Property(notification => notification.ReadAt)
                .IsRequired(false);

            entity.HasOne<ApplicationUser>()
                .WithMany()
                .HasForeignKey(notification => notification.RecipientId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasIndex(notification => new
            {
                notification.RecipientId,
                notification.CreatedAt
            });

            entity.HasIndex(notification => new
            {
                notification.RecipientId,
                notification.ReadAt
            });

            entity.HasIndex(notification => notification.EventType);
        });

        // =========================================================
        // PROPERTIES
        // =========================================================
        modelBuilder.Entity<Property>(entity =>
        {
            entity.HasKey(property => property.Id);

            entity.Property(property => property.LandlordId)
                .IsRequired();

            entity.Property(property => property.Title)
                .HasMaxLength(200)
                .IsRequired();

            entity.Property(property => property.Description)
                .HasMaxLength(2000)
                .IsRequired();

            entity.Property(property => property.Address)
                .HasMaxLength(500)
                .IsRequired();

            entity.Property(property => property.City)
                .HasMaxLength(100)
                .IsRequired();

            entity.Property(property => property.MonthlyRent)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(property => property.Bedrooms)
                .IsRequired();

            entity.Property(property => property.Bathrooms)
                .IsRequired();

            entity.Property(property => property.IsAvailable)
                .IsRequired();

            entity.Property(property => property.CreatedAt)
                .IsRequired();

            entity.Property(property => property.UpdatedAt)
                .IsRequired(false);

            entity.HasOne(property => property.Landlord)
                .WithMany()
                .HasForeignKey(property => property.LandlordId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(property => property.LandlordId);
            entity.HasIndex(property => property.City);
            entity.HasIndex(property => property.MonthlyRent);
            entity.HasIndex(property => property.IsAvailable);
        });

        // =========================================================
        // PROPERTY AMENITIES
        // =========================================================
        modelBuilder.Entity<PropertyAmenity>(entity =>
        {
            entity.HasKey(amenity => amenity.Id);

            entity.Property(amenity => amenity.PropertyId)
                .IsRequired();

            entity.Property(amenity => amenity.Name)
                .HasMaxLength(100)
                .IsRequired();

            entity.HasOne(amenity => amenity.Property)
                .WithMany(property => property.Amenities)
                .HasForeignKey(amenity => amenity.PropertyId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasIndex(amenity => amenity.PropertyId);
        });

        // =========================================================
        // PROPERTY IMAGES
        // =========================================================
        modelBuilder.Entity<PropertyImage>(entity =>
        {
            entity.HasKey(image => image.Id);

            entity.Property(image => image.PropertyId)
                .IsRequired();

            entity.Property(image => image.OriginalFileName)
                .HasMaxLength(255)
                .IsRequired();

            entity.Property(image => image.StorageKey)
                .HasMaxLength(512)
                .IsRequired();

            entity.Property(image => image.ContentType)
                .HasMaxLength(255)
                .IsRequired();

            entity.Property(image => image.FileSizeBytes)
                .IsRequired();

            entity.Property(image => image.UploadedAt)
                .IsRequired();

            entity.HasOne(image => image.Property)
                .WithMany(property => property.Images)
                .HasForeignKey(image => image.PropertyId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasIndex(image => image.PropertyId);
        });

        // =========================================================
        // VIEWING REQUESTS
        // =========================================================
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

        // =========================================================
        // RENTAL APPLICATIONS
        // =========================================================
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

        // =========================================================
        // RENTAL OFFERS
        // =========================================================
        modelBuilder.Entity<RentalOffer>(entity =>
        {
            entity.HasKey(offer => offer.Id);

            entity.Property(offer => offer.RentalApplicationId)
                .IsRequired();

            entity.Property(offer => offer.TenantId)
                .IsRequired();

            entity.Property(offer => offer.PropertyId)
                .IsRequired();

            entity.Property(offer => offer.MonthlyRent)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(offer => offer.SecurityDeposit)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(offer => offer.ProposedStartDate)
                .IsRequired();

            entity.Property(offer => offer.ProposedEndDate)
                .IsRequired();

            entity.Property(offer => offer.ExpiresAt)
                .IsRequired();

            entity.Property(offer => offer.Status)
                .IsRequired();

            entity.Property(offer => offer.LandlordNote)
                .HasMaxLength(1000)
                .IsRequired(false);

            entity.Property(offer => offer.CreatedAt)
                .IsRequired();

            entity.Property(offer => offer.UpdatedAt)
                .IsRequired(false);

            entity.HasOne(offer => offer.RentalApplication)
                .WithMany()
                .HasForeignKey(offer => offer.RentalApplicationId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne<Property>()
                .WithMany()
                .HasForeignKey(offer => offer.PropertyId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(offer => offer.RentalApplicationId);
            entity.HasIndex(offer => offer.TenantId);
            entity.HasIndex(offer => offer.PropertyId);
            entity.HasIndex(offer => offer.Status);
        });

        // =========================================================
        // LEASE AGREEMENTS
        // =========================================================
        modelBuilder.Entity<LeaseAgreement>(entity =>
        {
            entity.HasKey(lease => lease.Id);

            entity.Property(lease => lease.RentalOfferId)
                .IsRequired();

            entity.Property(lease => lease.TenantId)
                .IsRequired();

            entity.Property(lease => lease.PropertyId)
                .IsRequired();

            entity.Property(lease => lease.MonthlyRent)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(lease => lease.SecurityDeposit)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(lease => lease.StartDate)
                .IsRequired();

            entity.Property(lease => lease.EndDate)
                .IsRequired();

            entity.Property(lease => lease.Status)
                .IsRequired();

            entity.Property(lease => lease.CreatedAt)
                .IsRequired();

            entity.Property(lease => lease.UpdatedAt)
                .IsRequired(false);

            entity.HasOne(lease => lease.RentalOffer)
                .WithMany()
                .HasForeignKey(lease => lease.RentalOfferId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne<Property>()
                .WithMany()
                .HasForeignKey(lease => lease.PropertyId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(lease => lease.RentalOfferId)
                .IsUnique();

            entity.HasIndex(lease => lease.TenantId);
            entity.HasIndex(lease => lease.PropertyId);
            entity.HasIndex(lease => lease.Status);
        });

        // =========================================================
        // RENT SCHEDULE ITEMS
        // =========================================================
        modelBuilder.Entity<RentScheduleItem>(entity =>
        {
            entity.HasKey(item => item.Id);

            entity.Property(item => item.LeaseAgreementId)
                .IsRequired();

            entity.Property(item => item.DueDate)
                .IsRequired();

            entity.Property(item => item.Amount)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(item => item.Status)
                .IsRequired();

            entity.Property(item => item.CreatedAt)
                .IsRequired();

            entity.Property(item => item.UpdatedAt)
                .IsRequired(false);

            entity.HasOne(item => item.LeaseAgreement)
                .WithMany()
                .HasForeignKey(item => item.LeaseAgreementId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(item => item.LeaseAgreementId);
            entity.HasIndex(item => item.DueDate);
            entity.HasIndex(item => item.Status);

            entity.HasIndex(item => new
            {
                item.LeaseAgreementId,
                item.DueDate
            })
            .IsUnique();
        });

        // =========================================================
        // APPLICATION DOCUMENTS
        // =========================================================
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

        // =========================================================
        // APPLICATION VALIDATION WORKFLOWS
        // =========================================================
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

        // =========================================================
        // APPLICATION VALIDATION STEPS
        // =========================================================
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

            entity.HasIndex(step => new
            {
                step.WorkflowId,
                step.StepOrder
            })
            .IsUnique();
        });

        // =========================================================
        // PAYMENTS
        // =========================================================
        modelBuilder.Entity<Payment>(entity =>
        {
            entity.HasKey(payment => payment.Id);

            entity.Property(payment => payment.RentScheduleItemId)
                .IsRequired();

            entity.Property(payment => payment.TenantId)
                .IsRequired();

            entity.Property(payment => payment.Amount)
                .HasPrecision(18, 2)
                .IsRequired();

            entity.Property(payment => payment.PaymentMethod)
                .HasMaxLength(100)
                .IsRequired();

            entity.Property(payment => payment.TransactionReference)
                .HasMaxLength(200)
                .IsRequired(false);

            entity.Property(payment => payment.Status)
                .IsRequired();

            entity.Property(payment => payment.PaidAt)
                .IsRequired(false);

            entity.Property(payment => payment.CreatedAt)
                .IsRequired();

            entity.Property(payment => payment.UpdatedAt)
                .IsRequired(false);

            entity.HasOne(payment => payment.RentScheduleItem)
                .WithMany()
                .HasForeignKey(payment => payment.RentScheduleItemId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(payment => payment.RentScheduleItemId);
            entity.HasIndex(payment => payment.RentScheduleItemId, "IX_Payments_RentScheduleItemId_Completed")
                .IsUnique()
                .HasFilter("\"Status\" = 1");
            entity.HasIndex(payment => payment.TenantId);
            entity.HasIndex(payment => payment.Status);
            entity.HasIndex(payment => payment.TransactionReference);
        });

        modelBuilder.Entity<MaintenanceCoordinationWorkflow>(entity =>
        {
            entity.HasKey(workflow => workflow.Id);

            entity.Property(workflow => workflow.MaintenanceRequestId)
                .IsRequired();

            entity.Property(workflow => workflow.Objective)
                .HasMaxLength(2000)
                .IsRequired();

            entity.Property(workflow => workflow.Status)
                .IsRequired();

            entity.Property(workflow => workflow.CurrentStep)
                .IsRequired();

            entity.Property(workflow => workflow.AgentVersion)
                .HasMaxLength(200)
                .IsRequired(false);

            entity.Property(workflow => workflow.PlanSummary)
                .HasMaxLength(4000)
                .IsRequired(false);

            entity.Property(workflow => workflow.ExecutionSummary)
                .HasMaxLength(4000)
                .IsRequired(false);

            entity.Property(workflow => workflow.FinalResultJson)
                .HasColumnType("text")
                .IsRequired(false);

            entity.Property(workflow => workflow.ErrorMessage)
                .HasMaxLength(4000)
                .IsRequired(false);

            entity.Property(workflow => workflow.RequiresHumanApproval)
                .IsRequired();

            entity.Property(workflow => workflow.ApprovalStatus)
                .IsRequired();

            entity.Property(workflow => workflow.CreatedAt)
                .IsRequired();

            entity.Property(workflow => workflow.UpdatedAt)
                .IsRequired();

            entity.HasOne(workflow => workflow.MaintenanceRequest)
                .WithMany()
                .HasForeignKey(workflow => workflow.MaintenanceRequestId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(workflow => workflow.MaintenanceRequestId);
        });

        modelBuilder.Entity<MaintenanceCoordinationStep>(entity =>
        {
            entity.HasKey(step => step.Id);

            entity.Property(step => step.WorkflowId)
                .IsRequired();

            entity.Property(step => step.StepName)
                .HasMaxLength(200)
                .IsRequired();

            entity.Property(step => step.StepOrder)
                .IsRequired();

            entity.Property(step => step.Status)
                .IsRequired();

            entity.Property(step => step.InputSummary)
                .HasMaxLength(4000)
                .IsRequired(false);

            entity.Property(step => step.OutputSummary)
                .HasMaxLength(4000)
                .IsRequired(false);

            entity.Property(step => step.ValidationSummary)
                .HasMaxLength(4000)
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
