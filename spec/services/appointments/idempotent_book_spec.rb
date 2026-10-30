require "rails_helper"

RSpec.describe Appointments::IdempotentBook do
  let(:book) { instance_double(Appointments::Book) }
  let(:service) { described_class.new(book:) }
  let(:appointment) { create(:appointment) }
  let(:params) { { "customer_id" => "c", "start_at" => "2030-01-07T09:00:00Z" } }

  before { allow(book).to receive(:call).and_return(Dry::Monads::Success(appointment)) }

  it "AC17 stores the first success and replays it without booking again" do
    first = service.call(key: "idem-ac17", params:)
    second = service.call(key: "idem-ac17", params:)

    expect(first).to be_success
    expect(second.value!.deep_stringify_keys).to eq(first.value!.deep_stringify_keys)
    expect(book).to have_received(:call).once
    row = IdempotencyKey.find_by!(key: "idem-ac17")
    expect(row.response_status).to eq(201)
    expect(row.appointment_id).to eq(appointment.id)
  end

  it "AC17 treats param key order as irrelevant" do
    service.call(key: "idem-order", params:)

    expect(service.call(key: "idem-order", params: params.to_a.reverse.to_h)).to be_success
    expect(book).to have_received(:call).once
  end

  it "EC13 fails with IDEMPOTENCY_KEY_REUSED for another payload" do
    service.call(key: "idem-ec13", params:)

    result = service.call(key: "idem-ec13", params: params.merge("start_at" => "2030-01-07T11:00:00Z"))

    expect(result.failure.first).to eq("IDEMPOTENCY_KEY_REUSED")
    expect(book).to have_received(:call).once
  end

  it "EC14 does not store failures" do
    allow(book).to receive(:call).and_return(Dry::Monads::Failure([ "NO_BAY", { detail: "x", errors: nil, extra: nil } ]))

    result = service.call(key: "idem-ec14", params:)

    expect(result.failure.first).to eq("NO_BAY")
    expect(IdempotencyKey.where(key: "idem-ec14")).to be_empty
  end

  it "EC14 books on retry after a failure" do
    allow(book).to receive(:call).and_return(Dry::Monads::Failure([ "NO_BAY", { detail: "x", errors: nil, extra: nil } ]), Dry::Monads::Success(appointment))

    service.call(key: "idem-retry", params:)

    expect(service.call(key: "idem-retry", params:)).to be_success
  end

  it "EC15 fails with IDEMPOTENCY_KEY_IN_PROGRESS for an unfinished row" do
    fingerprint = Digest::SHA256.hexdigest(JSON.generate(params.sort.to_h))
    create(:idempotency_key, key: "idem-ec15", request_fingerprint: fingerprint)

    result = service.call(key: "idem-ec15", params:)

    expect(result.failure.first).to eq("IDEMPOTENCY_KEY_IN_PROGRESS")
    expect(book).not_to have_received(:call)
  end

  it "EC15 rejects a key longer than 255 characters" do
    result = service.call(key: "k" * 256, params:)

    expect(result.failure.first).to eq("VALIDATION_ERROR")
    expect(result.failure.last[:errors]).to eq("Idempotency-Key" => [ "is too long (maximum is 255 characters)" ])
  end

  it "EC15 books without storing anything for a blank key" do
    expect(service.call(key: "", params:)).to be_success
    expect(service.call(key: nil, params:)).to be_success
    expect(IdempotencyKey.count).to eq(0)
  end
end
