require "rails_helper"

RSpec.describe ExpiredIdempotencyKeysCleanupJob do
  let(:now) { Time.utc(2030, 1, 1) }

  before { allow(Clock).to receive(:now).and_return(now) }

  it "deletes keys older than the default TTL and keeps newer ones" do
    old_key = create(:idempotency_key, created_at: now - 86_401)
    fresh_key = create(:idempotency_key, created_at: now - 86_399)

    described_class.perform_now

    expect(IdempotencyKey.where(id: [ old_key.id, fresh_key.id ])).to contain_exactly(fresh_key)
  end

  it "honours IDEMPOTENCY_TTL" do
    stub_const("ENV", ENV.to_h.merge("IDEMPOTENCY_TTL" => "60"))
    old_key = create(:idempotency_key, created_at: now - 61)
    fresh_key = create(:idempotency_key, created_at: now - 59)

    described_class.perform_now

    expect(IdempotencyKey.where(id: [ old_key.id, fresh_key.id ])).to contain_exactly(fresh_key)
  end

  it "uses the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end
end
