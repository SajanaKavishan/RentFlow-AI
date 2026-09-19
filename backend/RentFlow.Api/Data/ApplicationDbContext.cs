using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Models;

namespace RentFlow.Api.Data;

public class ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
    : DbContext(options)
{
    public DbSet<ApplicationUser> Users => Set<ApplicationUser>();

    public DbSet<Property> Properties => Set<Property>();

    public DbSet<PropertyAmenity> PropertyAmenities => Set<PropertyAmenity>();

    public DbSet<PropertyImage> PropertyImages => Set<PropertyImage>();

    public DbSet<ViewingRequest> ViewingRequests => Set<ViewingRequest>();

    public DbSet<RentalApplication> RentalApplications => Set<RentalApplication>();

    public DbSet<ApplicationDocument> ApplicationDocuments => Set<ApplicationDocument>();

    public DbSet<ApplicationValidationWorkflow> ApplicationValidationWorkflows =>
        Set<ApplicationValidationWorkflow>();

    public DbSet<ApplicationValidationStep> ApplicationValidationSteps =>
        Set<ApplicationValidationStep>();

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
    }
}