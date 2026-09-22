import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';

Issue _issue(List<String> customers) => Issue(
  id: 'i-${customers.join('-')}',
  projectId: 'p',
  reference: 1,
  subject: 'subject',
  description: '',
  labels: const [],
  components: const [],
  customerIds: customers,
  order: 1,
  version: 1,
  createdAt: DateTime(2026),
  modifiedAt: DateTime(2026),
);

void main() {
  const closed = <String>{};

  test('no customer filter matches everything', () {
    const f = WorkItemFilter();
    expect(f.matches(_issue(const []), closedStatusIds: closed), isTrue);
    expect(f.matches(_issue(const ['a']), closedStatusIds: closed), isTrue);
    expect(f.isActive, isFalse);
  });

  test('a customer id matches issues linked to it among others', () {
    const f = WorkItemFilter(customerId: 'a');
    expect(f.isActive, isTrue);
    expect(f.matches(_issue(const ['a']), closedStatusIds: closed), isTrue);
    expect(
      f.matches(_issue(const ['b', 'a']), closedStatusIds: closed),
      isTrue,
    );
    expect(f.matches(_issue(const ['b']), closedStatusIds: closed), isFalse);
    expect(f.matches(_issue(const []), closedStatusIds: closed), isFalse);
  });

  test("'none' matches only issues without customers", () {
    const f = WorkItemFilter(customerId: 'none');
    expect(f.matches(_issue(const []), closedStatusIds: closed), isTrue);
    expect(f.matches(_issue(const ['a']), closedStatusIds: closed), isFalse);
  });

  test('the customer dimension round-trips under the API query key', () {
    const f = WorkItemFilter(customerId: 'a');
    expect(f.toJson(), {'customer': 'a'});
    expect(WorkItemFilter.decode(f.encode()).customerId, 'a');
    expect(f.copyWith(customerId: null).customerId, isNull);
    expect(f.copyWith(search: 'x').customerId, 'a');
  });
}
