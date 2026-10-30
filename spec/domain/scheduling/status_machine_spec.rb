RSpec.describe Scheduling::StatusMachine do
  let(:statuses) { described_class::STATUSES }
  let(:allowed_pairs) do
    [
      %w[confirmed in_progress],
      %w[confirmed cancelled],
      %w[confirmed no_show],
      %w[in_progress completed]
    ]
  end

  it "AC10 allows exactly the four documented transitions across every pair" do
    statuses.product(statuses).each do |from, to|
      expect(described_class.allowed?(from:, to:)).to eq(allowed_pairs.include?([ from, to ])), "#{from} -> #{to}"
    end
  end

  it "AC10 accepts symbols as well as strings" do
    expect(described_class.allowed?(from: :confirmed, to: :in_progress)).to be(true)
    expect(described_class.allowed_from(:in_progress)).to eq(%w[completed])
  end

  it "AC10 lists the allowed targets per status" do
    expect(described_class.allowed_from("confirmed")).to eq(%w[in_progress cancelled no_show])
    expect(described_class.allowed_from("completed")).to eq([])
  end

  it "AC10 returns no targets for an unknown status" do
    expect(described_class.allowed_from("bogus")).to eq([])
    expect(described_class.allowed?(from: "bogus", to: "completed")).to be(false)
  end

  it "AC10 holds resources only for confirmed and in_progress" do
    held = statuses.select { |status| described_class.holds_resources?(status) }

    expect(held).to contain_exactly("confirmed", "in_progress")
    expect(described_class.holds_resources?(:confirmed)).to be(true)
    expect(described_class.holds_resources?("bogus")).to be(false)
  end

  it "AC10 exposes frozen tables" do
    expect(described_class::TRANSITIONS).to be_frozen
    expect(described_class::TRANSITIONS.values).to all(be_frozen)
  end
end
