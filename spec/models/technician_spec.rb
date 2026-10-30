require "rails_helper"

RSpec.describe Technician do
  subject { build(:technician) }

  it { is_expected.to belong_to(:dealership) }
  it { is_expected.to have_many(:technician_qualifications).dependent(:destroy) }
  it { is_expected.to have_many(:qualifications).through(:technician_qualifications) }
  it { is_expected.to have_many(:technician_shifts).dependent(:destroy) }
  it { is_expected.to have_many(:technician_time_offs).dependent(:destroy) }
  it { is_expected.to have_many(:appointments).dependent(:restrict_with_error) }
  it { is_expected.to validate_presence_of(:name) }
end
