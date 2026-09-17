using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Models;

namespace RentFlow.Api.Data;

public class ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : DbContext(options)
{
    public DbSet<ApplicationUser> Users => Set<ApplicationUser>();

    public DbSet<ViewingRequest> ViewingRequests => Set<ViewingRequest>();

    public DbSet<RentalApplication> RentalApplications => Set<RentalApplication>();

    public DbSet<RentalOffer> RentalOffers => Set<RentalOffer>();

    public DbSet<LeaseAgreement> LeaseAgreements => Set<LeaseAgreement>();

    public DbSet<ApplicationDocument> ApplicationDocuments => Set<ApplicationDocument>();

    public DbSet<ApplicationValidationWorkflow> ApplicationValidationWorkflows => Set<ApplicationValidationWorkflow>();

    public DbSet<ApplicationValidationStep> ApplicationValidationSteps => Set<ApplicationValidationStep>();

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

            entity.HasIndex(offer => offer.RentalApplicationId);
            entity.HasIndex(offer => offer.TenantId);
            entity.HasIndex(offer => offer.PropertyId);
            entity.HasIndex(offer => offer.Status);
        });

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

            entity.HasIndex(lease => lease.RentalOfferId)
                .IsUnique();

            entity.HasIndex(lease => lease.TenantId);

            entity.HasIndex(lease => lease.PropertyId);

            entity.HasIndex(lease => lease.Status);
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
    }
}
