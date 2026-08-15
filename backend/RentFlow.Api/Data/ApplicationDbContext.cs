using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Models;

namespace RentFlow.Api.Data;

public class ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : DbContext(options)
{
    public DbSet<ViewingRequest> ViewingRequests => Set<ViewingRequest>();

    public DbSet<RentalApplication> RentalApplications => Set<RentalApplication>();

    public DbSet<ApplicationDocument> ApplicationDocuments => Set<ApplicationDocument>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

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
    }
}
