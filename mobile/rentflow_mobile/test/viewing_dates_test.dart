import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/viewings/models/viewing_dates.dart';

Map<String, dynamic> _response() => {
  'propertyId': 'property-id',
  'timeZoneId': 'Asia/Colombo',
  'firstDate': '2030-10-06',
  'lastDate': '2031-10-06',
  'availableDates': ['2030-10-07', '2030-11-09', '2030-10-07'],
  'state': 'available',
};

void main() {
  test('distinct property-local dates retain calendar components', () {
    final dates = ViewingDates.fromJson(_response());
    expect(dates.availableDates, {
      DateTime(2030, 10, 7),
      DateTime(2030, 11, 9),
    });
    expect(dates.isSelectable(DateTime(2030, 10, 7, 23, 59)), isTrue);
    expect(dates.isSelectable(DateTime.utc(2030, 11, 9)), isTrue);
    expect(dates.isSelectable(DateTime(2030, 10, 8)), isFalse);
    expect(dates.isSelectable(DateTime(2031, 10, 7)), isFalse);
    expect(
      () => dates.availableDates.add(DateTime(2030, 10, 8)),
      throwsUnsupportedError,
    );
  });

  for (final invalid in [
    '2030-02-30',
    '2030-13-01',
    '2030-10-07T00:00:00Z',
    '2030-10-05',
    '2031-10-07',
  ]) {
    test('rejects invalid or out-of-range backend date $invalid', () {
      final response = _response()..['availableDates'] = [invalid];
      expect(() => ViewingDates.fromJson(response), throwsFormatException);
    });
  }

  test('empty and unconfigured responses never enable dates', () {
    for (final state in ['empty', 'unconfigured']) {
      final response = _response()
        ..['availableDates'] = <String>[]
        ..['state'] = state;
      final dates = ViewingDates.fromJson(response);
      expect(dates.availableDates, isEmpty);
      expect(dates.isSelectable(DateTime(2030, 10, 7)), isFalse);
    }
  });

  test('rejects reversed bounds and inconsistent availability', () {
    expect(
      () => ViewingDates.fromJson(_response()..['firstDate'] = '2032-10-06'),
      throwsFormatException,
    );
    expect(
      () => ViewingDates.fromJson(_response()..['availableDates'] = <String>[]),
      throwsFormatException,
    );
    expect(
      () => ViewingDates.fromJson(_response()..['state'] = 'empty'),
      throwsFormatException,
    );
  });
}
