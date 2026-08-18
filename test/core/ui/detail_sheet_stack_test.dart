import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/ui/detail_sheet_stack.dart';

/// Detail sheets layer on top of each other, so the registry is the only thing
/// standing between "milestone → epic → task" and an endless tower of panels
/// for the same two entities linking to each other.
void main() {
  setUp(DetailSheetStack.reset);
  tearDown(DetailSheetStack.reset);

  test('an entity already open is refused, a different one is not', () {
    final epic = detailSheetKey('epic', 'e1');
    final issue = detailSheetKey('issue', 'i1');

    expect(DetailSheetStack.contains(epic), isFalse);
    DetailSheetStack.push(epic);
    expect(DetailSheetStack.contains(epic), isTrue);
    // The recursion case: the epic lists this issue, the issue links back to
    // the epic. The issue may open; the epic may not open again.
    expect(DetailSheetStack.contains(issue), isFalse);
    DetailSheetStack.push(issue);
    expect(DetailSheetStack.contains(epic), isTrue);
  });

  test('the same id under a different kind is a different sheet', () {
    DetailSheetStack.push(detailSheetKey('epic', 'x'));
    expect(DetailSheetStack.contains(detailSheetKey('issue', 'x')), isFalse);
  });

  test('depth counts the open sheets and drives the nesting inset', () {
    expect(DetailSheetStack.depth, 0);
    DetailSheetStack.push(detailSheetKey('milestone', 'm1'));
    DetailSheetStack.push(detailSheetKey('epic', 'e1'));
    DetailSheetStack.push(detailSheetKey('issue', 'i1'));
    expect(DetailSheetStack.depth, 3);
  });

  test('closing releases the key so the entity can be opened again', () {
    final key = detailSheetKey('issue', 'i1');
    DetailSheetStack.push(key);
    DetailSheetStack.pop(key);
    expect(DetailSheetStack.contains(key), isFalse);
    expect(DetailSheetStack.depth, 0);
    DetailSheetStack.push(key);
    expect(DetailSheetStack.contains(key), isTrue);
  });

  test('sheets close out of order without stranding an outer entry', () {
    final outer = detailSheetKey('milestone', 'm1');
    final inner = detailSheetKey('epic', 'e1');
    DetailSheetStack.push(outer);
    DetailSheetStack.push(inner);
    // A barrier tap can dismiss routes in an order the caller did not choose.
    DetailSheetStack.pop(outer);
    DetailSheetStack.pop(inner);
    expect(DetailSheetStack.depth, 0);
    expect(DetailSheetStack.contains(outer), isFalse);
    expect(DetailSheetStack.contains(inner), isFalse);
  });

  test('popping something never pushed is harmless', () {
    DetailSheetStack.pop(detailSheetKey('issue', 'ghost'));
    expect(DetailSheetStack.depth, 0);
  });
}
