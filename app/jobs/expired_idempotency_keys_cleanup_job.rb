class ExpiredIdempotencyKeysCleanupJob < ApplicationJob
  queue_as :default

  def perform
    ttl = Integer(ENV.fetch("IDEMPOTENCY_TTL", "86400"))
    IdempotencyKey.where(created_at: ...(Clock.now - ttl)).in_batches(of: 1_000).delete_all
  end
end
