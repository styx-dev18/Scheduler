require "rails_helper"

RSpec.describe TechnicianQualification do
  subject { create(:technician_qualification) }

  it { is_expected.to belong_to(:technician) }
  it { is_expected.to belong_to(:qualification) }
  it { is_expected.to validate_uniqueness_of(:qualification_id).scoped_to(:technician_id).ignoring_case_sensitivity }
end
