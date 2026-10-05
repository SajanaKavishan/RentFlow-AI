import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/maintenance/models/maintenance_request.dart';
import 'package:rentflow_mobile/features/maintenance/models/repair_estimate.dart';

void main() {
  group('MaintenanceRequest', () {
    test('parses the optional display name without adding contact fields', () {
      final payload = <String, dynamic>{
        'id': 'request',
        'propertyId': 'property',
        'tenantId': 'tenant',
        'title': 'Leaking tap',
        'description': 'The kitchen tap is leaking.',
        'category': 0,
        'priority': 1,
        'status': 2,
        'createdAt': '2026-10-05T09:00:00Z',
        'technicianId': 'technician',
        'assignedTechnicianName': 'Mike Reyes',
      };
      expect(
        MaintenanceRequest.fromJson(payload).assignedTechnicianName,
        'Mike Reyes',
      );
      expect(
        MaintenanceRequest.fromSummaryJson(payload).assignedTechnicianName,
        'Mike Reyes',
      );
      expect(
        MaintenanceRequest.fromJson({
          ...payload,
          'assignedTechnicianName': null,
        }).assignedTechnicianName,
        isNull,
      );
      payload.remove('assignedTechnicianName');
      expect(
        MaintenanceRequest.fromJson(payload).assignedTechnicianName,
        isNull,
      );
      expect(
        () => MaintenanceRequest.fromJson({
          ...payload,
          'assignedTechnicianName': 42,
        }),
        throwsFormatException,
      );
    });
    test(
      'decodes new fields and keeps legacy Low/Security payloads readable',
      () {
        final legacy = <String, dynamic>{
          'id': '11efbe01-9196-44b6-b1b2-73767fae5cf1',
          'propertyId': 'property',
          'tenantId': 'tenant',
          'title': 'Legacy request',
          'description': 'Old issue',
          'category': 4,
          'priority': 0,
          'status': 0,
          'createdAt': '2026-10-05T09:00:00Z',
        };
        final old = MaintenanceRequest.fromJson(legacy);
        expect(old.referenceCode, isNull);
        expect(old.preferredAccessWindow, isNull);
        expect(old.category, MaintenanceCategory.security);
        expect(old.priority, MaintenancePriority.low);
        for (final category in [7, 8]) {
          final current = {
            ...legacy,
            'category': category,
            'referenceCode': 'MR-C8070B6D94F6A810',
            'preferredAccessWindow': 'Afternoon',
          };
          final full = MaintenanceRequest.fromJson(current);
          final summary = MaintenanceRequest.fromSummaryJson(current);
          expect(full.category.value, category);
          expect(summary.referenceCode, full.referenceCode);
          expect(
            summary.preferredAccessWindow,
            PreferredAccessWindow.afternoon,
          );
          expect(PreferredAccessWindow.afternoon.apiValue, 'Afternoon');
        }
        expect(
          () => MaintenanceRequest.fromJson({
            ...legacy,
            'preferredAccessWindow': 'Night',
          }),
          throwsFormatException,
        );
        expect(
          () => MaintenanceRequest.fromJson({
            ...legacy,
            'referenceCode': legacy['id'],
          }),
          throwsFormatException,
        );
      },
    );
    test('parses a valid maintenance request payload', () {
      final json = <String, dynamic>{
        'id': '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
        'propertyId': 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0',
        'tenantId': 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
        'technicianId': 'd0f76d69-b415-4900-a6a8-7d11df8bb34c',
        'title': 'Kitchen sink leak',
        'description': 'Water is leaking under the sink cabinet.',
        'category': 0,
        'priority': 2,
        'status': 3,
        'tenantAccessNotes': 'Use the back door.',
        'triageNotes': 'Check for pipe seal issue.',
        'assignmentNotes': 'Technician to visit Monday morning.',
        'cancellationReason': null,
        'completedAt': null,
        'createdAt': '2026-09-17T08:15:00Z',
        'updatedAt': '2026-09-18T10:00:00Z',
      };

      final request = MaintenanceRequest.fromJson(json);

      expect(request.id, '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200');
      expect(request.propertyId, 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0');
      expect(request.tenantId, 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff');
      expect(request.technicianId, 'd0f76d69-b415-4900-a6a8-7d11df8bb34c');
      expect(request.title, 'Kitchen sink leak');
      expect(request.description, 'Water is leaking under the sink cabinet.');
      expect(request.category, MaintenanceCategory.plumbing);
      expect(request.priority, MaintenancePriority.high);
      expect(request.status, MaintenanceRequestStatus.estimatePending);
      expect(request.tenantAccessNotes, 'Use the back door.');
      expect(request.triageNotes, 'Check for pipe seal issue.');
      expect(request.assignmentNotes, 'Technician to visit Monday morning.');
      expect(request.cancellationReason, isNull);
      expect(request.completedAt, isNull);
      expect(request.createdAt, DateTime.utc(2026, 9, 17, 8, 15));
      expect(request.updatedAt, DateTime.utc(2026, 9, 18, 10, 0));
    });

    test('parses all enum values', () {
      for (final entry in MaintenanceRequestStatus.values) {
        expect(MaintenanceRequestStatus.fromJson(entry.value), entry);
      }

      for (final entry in MaintenanceCategory.values) {
        expect(MaintenanceCategory.fromJson(entry.value), entry);
      }

      for (final entry in MaintenancePriority.values) {
        expect(MaintenancePriority.fromJson(entry.value), entry);
      }
    });

    test('throws FormatException for missing required values', () {
      final invalid = <String, dynamic>{
        'id': '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
        'propertyId': 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0',
        'tenantId': 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
        'title': 'Kitchen sink leak',
        'category': 0,
        'priority': 2,
        'status': 3,
        'createdAt': '2026-09-17T08:15:00Z',
      };

      expect(
        () => MaintenanceRequest.fromJson(invalid),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for invalid enum values', () {
      final invalidStatus = <String, dynamic>{
        'id': '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
        'propertyId': 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0',
        'tenantId': 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
        'title': 'Kitchen sink leak',
        'description': 'Water is leaking under the sink cabinet.',
        'category': 0,
        'priority': 2,
        'status': 999,
        'createdAt': '2026-09-17T08:15:00Z',
      };

      expect(
        () => MaintenanceRequest.fromJson(invalidStatus),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RepairEstimate', () {
    test('maps every persisted review status', () {
      for (final status in RepairEstimateStatus.values) {
        expect(RepairEstimateStatus.fromJson(status.value), status);
      }
    });

    test('parses a revision request and landlord review notes', () {
      final estimate = RepairEstimate.fromJson(
        _repairEstimateJson(
          status: RepairEstimateStatus.revisionRequested,
          reviewNotes: 'Please explain the parts cost.',
        ),
      );

      expect(estimate.status, RepairEstimateStatus.revisionRequested);
      expect(estimate.totalCost, 150.5);
      expect(estimate.reviewNotes, 'Please explain the parts cost.');
    });

    test('parses an estimate rejection state', () {
      final estimate = RepairEstimate.fromJson(
        _repairEstimateJson(
          status: RepairEstimateStatus.rejected,
          reviewNotes: 'Please use the approved supplier.',
        ),
      );

      expect(estimate.status, RepairEstimateStatus.rejected);
      expect(estimate.reviewNotes, 'Please use the approved supplier.');
    });
  });
}

Map<String, dynamic> _repairEstimateJson({
  required RepairEstimateStatus status,
  String? reviewNotes,
}) => {
  'id': 'estimate-1',
  'maintenanceRequestId': 'request-1',
  'technicianId': 'technician-1',
  'versionNumber': 1,
  'laborCost': 100.5,
  'partsCost': 40,
  'additionalCost': 10,
  'totalCost': 150.5,
  'notes': 'Replace the valve.',
  'status': status.value,
  'createdAt': '2026-09-19T08:15:00Z',
  'submittedAt': '2026-09-19T08:20:00Z',
  'reviewedAt':
      status == RepairEstimateStatus.revisionRequested ||
          status == RepairEstimateStatus.rejected
      ? '2026-09-20T08:20:00Z'
      : null,
  'reviewNotes': reviewNotes,
};
