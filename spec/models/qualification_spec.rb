require "rails_helper"

RSpec.describe Qualification do
  subject { build(:qualification) }

  it { is_expected.to have_many(:technician_qualifications).dependent(:destroy) }
  it { is_expected.to have_many(:technicians).through(:technician_qualifications) }
  it { is_expected.to have_many(:service_types).with_foreign_key(:required_qualification_id).dependent(:restrict_with_error) }
  it { is_expected.to validate_presence_of(:code) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_uniqueness_of(:code) }
end
