import 'package:flutter_test/flutter_test.dart';
import 'package:swapcycle/core/data/demo_store.dart';
import 'package:swapcycle/core/errors/app_exception.dart';
import 'package:swapcycle/features/items/domain/item.dart';
import 'package:swapcycle/features/swaps/domain/swap_offer.dart';
import 'package:swapcycle/features/swaps/domain/swap_rules.dart';

void main() {
  final now = DateTime.utc(2026, 11, 2, 8);
  SwapOffer offer({
    SwapStatus status = SwapStatus.pending,
    DateTime? firstConfirmation,
    Meetup? meetup,
    String? cancelledBy,
  }) => SwapOffer(
    id: 'offer',
    requesterId: 'a',
    recipientId: 'b',
    offeredItemId: 'one',
    requestedItemId: 'two',
    createdAt: now.subtract(const Duration(days: 1)),
    expiresAt: now.add(const Duration(days: 1)),
    events: const [],
    status: status,
    requesterConfirmedAt: firstConfirmation,
    cancellationRequestedBy: cancelledBy,
    meetup: meetup,
  );
  final agreed = Meetup(
    location: 'Perpustakaan kota',
    scheduledAt: now,
    proposedBy: 'a',
    approvedBy: 'b',
  );
  Matcher code(String expected) =>
      isA<AppException>().having((error) => error.code, 'code', expected);
  SwapStatus act(SwapOffer value, SwapAction action, String actor) =>
      SwapRules.transition(
        offer: value,
        action: action,
        actorId: actor,
        now: now,
      );

  group('Permission and terminal states', () {
    test('recipient accepts a pending offer', () {
      expect(act(offer(), SwapAction.accept, 'b'), SwapStatus.accepted);
    });
    test('requester cannot accept own offer', () {
      expect(
        () => act(offer(), SwapAction.accept, 'a'),
        throwsA(code('INVALID_TRANSITION')),
      );
    });
    test('third party cannot mutate offer', () {
      expect(
        () => act(offer(), SwapAction.accept, 'c'),
        throwsA(code('NOT_PARTICIPANT')),
      );
    });
    test('requester withdraws; recipient declines', () {
      expect(act(offer(), SwapAction.withdraw, 'a'), SwapStatus.cancelled);
      expect(act(offer(), SwapAction.decline, 'b'), SwapStatus.declined);
      expect(
        () => act(offer(), SwapAction.withdraw, 'b'),
        throwsA(code('INVALID_TRANSITION')),
      );
    });
    test('accept fails at expiry boundary', () {
      final expired = SwapOffer(
        id: 'old',
        requesterId: 'a',
        recipientId: 'b',
        offeredItemId: 'one',
        requestedItemId: 'two',
        createdAt: now.subtract(const Duration(days: 7)),
        expiresAt: now,
        events: const [],
      );
      expect(
        () => act(expired, SwapAction.accept, 'b'),
        throwsA(code('EXPIRED')),
      );
    });
    test('terminal states reject reopening or cancellation', () {
      for (final status in SwapStatus.values.where(
        (value) => value.isTerminal,
      )) {
        expect(
          () => act(offer(status: status), SwapAction.accept, 'b'),
          throwsA(code('INVALID_TRANSITION')),
        );
        expect(
          () => act(offer(status: status), SwapAction.requestCancellation, 'a'),
          throwsA(code('INVALID_TRANSITION')),
        );
      }
    });
  });

  group('Physical handover', () {
    test('first confirmation never completes the transaction', () {
      expect(
        act(
          offer(status: SwapStatus.accepted, meetup: agreed),
          SwapAction.confirmReceipt,
          'a',
        ),
        SwapStatus.awaitingConfirmation,
      );
    });
    test('same participant retry never counts as second confirmation', () {
      expect(
        act(
          offer(
            status: SwapStatus.awaitingConfirmation,
            meetup: agreed,
            firstConfirmation: now,
          ),
          SwapAction.confirmReceipt,
          'a',
        ),
        SwapStatus.awaitingConfirmation,
      );
    });
    test('other participant confirmation completes', () {
      expect(
        act(
          offer(
            status: SwapStatus.awaitingConfirmation,
            meetup: agreed,
            firstConfirmation: now,
          ),
          SwapAction.confirmReceipt,
          'b',
        ),
        SwapStatus.completed,
      );
    });
    test('receipt needs no meetup and first claim keeps reservation', () {
      expect(
        act(offer(status: SwapStatus.accepted), SwapAction.confirmReceipt, 'a'),
        SwapStatus.awaitingConfirmation,
      );
      final unapproved = Meetup(
        location: 'Taman kota',
        scheduledAt: now,
        proposedBy: 'a',
      );
      expect(
        act(
          offer(status: SwapStatus.accepted, meetup: unapproved),
          SwapAction.confirmReceipt,
          'a',
        ),
        SwapStatus.awaitingConfirmation,
      );
    });
    test('future optional coordination does not block receipt', () {
      final future = Meetup(
        location: 'Taman kota',
        scheduledAt: now.add(const Duration(days: 1)),
        proposedBy: 'a',
        approvedBy: 'b',
      );
      expect(
        act(
          offer(status: SwapStatus.accepted, meetup: future),
          SwapAction.confirmReceipt,
          'a',
        ),
        SwapStatus.awaitingConfirmation,
      );
    });
    test('cancellation before handover needs agreement', () {
      expect(
        act(
          offer(status: SwapStatus.accepted),
          SwapAction.requestCancellation,
          'a',
        ),
        SwapStatus.cancellationRequested,
      );
      final requested = offer(
        status: SwapStatus.cancellationRequested,
        cancelledBy: 'a',
      );
      expect(
        () => act(requested, SwapAction.approveCancellation, 'a'),
        throwsA(code('INVALID_TRANSITION')),
      );
      expect(
        act(requested, SwapAction.approveCancellation, 'b'),
        SwapStatus.cancelled,
      );
      expect(
        act(requested, SwapAction.rejectCancellation, 'b'),
        SwapStatus.accepted,
      );
    });
    test('cancellation after a handover claim becomes a dispute', () {
      expect(
        act(
          offer(
            status: SwapStatus.awaitingConfirmation,
            firstConfirmation: now,
          ),
          SwapAction.requestCancellation,
          'b',
        ),
        SwapStatus.disputed,
      );
    });
    test('normal users cannot resolve a dispute', () {
      expect(
        () => act(
          offer(status: SwapStatus.disputed),
          SwapAction.approveCancellation,
          'b',
        ),
        throwsA(code('INVALID_TRANSITION')),
      );
      expect(
        () => act(
          offer(status: SwapStatus.disputed),
          SwapAction.confirmReceipt,
          'a',
        ),
        throwsA(code('INVALID_TRANSITION')),
      );
    });
  });

  group('Item ownership and search', () {
    late DemoStore store;
    setUp(() => store = DemoStore(clock: () => now));
    test('self exchange rejected', () async {
      final own = await store.find('plant');
      final otherOwn = await store.find('lamp');
      expect(
        () => SwapRules.validateItems(
          actorId: DemoStore.viewerId,
          offered: own,
          requested: otherOwn,
        ),
        throwsA(code('SELF_SWAP')),
      );
    });
    test('offered item must belong to actor', () async {
      expect(
        () async => SwapRules.validateItems(
          actorId: 'stranger',
          offered: await store.find('plant'),
          requested: await store.find('book'),
        ),
        throwsA(code('NOT_OWNER')),
      );
    });
    test('reserved, exchanged and hidden items rejected', () async {
      final own = await store.find('plant');
      final book = await store.find('book');
      for (final status in [
        ItemStatus.reserved,
        ItemStatus.exchanged,
        ItemStatus.archived,
        ItemStatus.draft,
      ]) {
        expect(
          () => SwapRules.validateItems(
            actorId: DemoStore.viewerId,
            offered: own,
            requested: book.copyWith(status: status),
          ),
          throwsA(code('ITEM_UNAVAILABLE')),
        );
      }
      expect(
        () => SwapRules.validateItems(
          actorId: DemoStore.viewerId,
          offered: own,
          requested: book.copyWith(visible: false),
        ),
        throwsA(code('ITEM_UNAVAILABLE')),
      );
    });
    test(
      'query, category and condition compose and exclude reserved',
      () async {
        final result = await store.search(
          const ItemFilter(
            query: '  ATOMIC  ',
            category: ItemCategory.books,
            condition: ItemCondition.good,
          ),
        );
        expect(result.map((item) => item.id), ['book']);
        expect(await store.search(const ItemFilter(query: 'yoga')), isEmpty);
        expect(
          await store.search(
            const ItemFilter(query: 'atomic', condition: ItemCondition.likeNew),
          ),
          isEmpty,
        );
      },
    );
  });
}
