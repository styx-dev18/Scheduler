RSpec.describe Scheduling::AssignmentStrategies::LeastLoaded do
  subject(:strategy) { described_class.new }

  let(:interval) do
    Scheduling::TimeInterval.new(starts_at: Time.utc(2030, 1, 7, 9), ends_at: Time.utc(2030, 1, 7, 10))
  end
  let(:bays) { [ "b2", "b1" ] }
  let(:technicians) { [ "t2", "t1", "t3" ] }
  let(:loads) { { "t1" => 2, "t2" => 1, "t3" => 1 } }

  it "picks the lowest bay and the least-loaded technician" do
    result = strategy.choose(bays:, technicians:, interval:, loads:)

    expect(result).to eq(Scheduling::Assignment.new(bay_id: "b1", technician_id: "t2"))
  end

  it "is deterministic across repeated calls" do
    results = Array.new(10) { strategy.choose(bays:, technicians:, interval:, loads:) }

    expect(results.uniq.size).to eq(1)
  end

  it "breaks ties by lowest id when loads are empty" do
    expect(strategy.choose(bays:, technicians:, interval:).technician_id).to eq("t1")
  end

  it "returns nil without bays" do
    expect(strategy.choose(bays: [], technicians:, interval:, loads:)).to be_nil
  end

  it "returns nil without technicians" do
    expect(strategy.choose(bays:, technicians: [], interval:, loads:)).to be_nil
  end
end
