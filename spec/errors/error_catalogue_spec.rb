require "rails_helper"

RSpec.describe ErrorCatalogue do
  let(:doc) { Rails.root.join("docs/error-catalogue.md").read }
  let(:openapi) { Rails.root.join("swagger/v1/openapi.yaml").read }

  it "AC1 documents every code in docs/error-catalogue.md" do
    missing = described_class::ENTRIES.keys.reject { |code| doc.include?("`#{code}`") }

    expect(missing).to eq([])
  end

  it "AC1 documents the status of every code" do
    mismatched = described_class::ENTRIES.values.reject do |entry|
      doc.lines.any? { |line| line.include?("`#{entry.code}`") && line.include?("| #{entry.status} |") }
    end

    expect(mismatched.map(&:code)).to eq([])
  end

  it "AC1 gives every entry a matching key, title and example" do
    invalid = described_class::ENTRIES.reject do |key, entry|
      entry.code == key && entry.title.present? && entry.example.present?
    end

    expect(invalid.keys).to eq([])
  end

  it "AC1 lists only catalogued codes in docs/error-catalogue.md" do
    documented = doc.scan(/^\| `([A-Z_]+)`/).flatten

    expect(documented - described_class::ENTRIES.keys).to eq([])
  end

  it "AC1 references only catalogued codes in swagger/v1/openapi.yaml" do
    referenced = openapi.scan(/\b[A-Z]{2,}(?:_[A-Z]+)+\b/).uniq

    expect(referenced - described_class::ENTRIES.keys).to eq([])
  end

  describe ".fetch" do
    it "AC1 returns the entry for a known code" do
      expect(described_class.fetch(:NO_BAY).status).to eq(409)
    end

    it "EC1 returns nil for an unknown code" do
      expect(described_class.fetch("UNKNOWN")).to be_nil
    end
  end
end
