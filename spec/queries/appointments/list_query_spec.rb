require "rails_helper"

RSpec.describe Appointments::ListQuery do
  let(:customer) { create(:customer) }
  let(:dealership) { create(:dealership) }

  def book(start_hour, day: 7, **attrs)
    create(:appointment, customer:, dealership:, start_at: Time.utc(2030, 1, day, start_hour),
                         end_at: Time.utc(2030, 1, day, start_hour + 1), **attrs)
  end

  it "AC7 filters by customer and sorts ascending by default" do
    late = book(11)
    early = book(9)
    create(:appointment)

    expect(described_class.new.call(customer_id: customer.id).map(&:id)).to eq([ early.id, late.id ])
  end

  it "AC7 sorts descending on request" do
    early = book(9)
    late = book(11)

    expect(described_class.new.call(customer_id: customer.id, direction: :desc).map(&:id)).to eq([ late.id, early.id ])
  end

  it "AC7 filters by status" do
    confirmed = book(9)
    book(11, status: "cancelled")

    expect(described_class.new.call(customer_id: customer.id, status: "confirmed").map(&:id)).to eq([ confirmed.id ])
  end

  it "AC7 treats from as inclusive and to as exclusive" do
    book(9, day: 7)
    inside = book(9, day: 8)
    book(9, day: 9)

    result = described_class.new.call(customer_id: customer.id, from: Time.utc(2030, 1, 8, 9), to: Time.utc(2030, 1, 9, 9))

    expect(result.map(&:id)).to eq([ inside.id ])
  end

  it "AC9 never returns another customer's appointments" do
    mine = book(9)
    create(:appointment, dealership:)

    expect(described_class.new.call(customer_id: customer.id).map(&:id)).to eq([ mine.id ])
  end

  it "EC10 returns an empty relation when the customer has none" do
    expect(described_class.new.call(customer_id: create(:customer).id)).to be_empty
  end

  it "AC9 preloads every association" do
    book(9)

    result = described_class.new.call(customer_id: customer.id).load

    expect(described_class::INCLUDES.map { |name| result.first.association(name).loaded? }).to all(be(true))
  end
end
