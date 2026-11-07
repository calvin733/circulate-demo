import 'swap_offer.dart';

abstract interface class SwapRepository {
  Future<List<SwapOffer>> listFor(String actorId);
  Future<SwapOffer> findOffer(String id, String actorId);
  Future<String> create({
    required String actorId,
    required String offeredItemId,
    required String requestedItemId,
    required String requestKey,
  });
  Future<void> act(String id, SwapAction action, String actorId);
  Future<void> proposeMeetup(
    String offerId,
    String actorId, {
    required String location,
    required DateTime scheduledAt,
  });
  Future<void> approveMeetup(String offerId, String actorId, Meetup proposal);
}
