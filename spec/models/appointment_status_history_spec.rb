require "rails_helper"

RSpec.describe AppointmentStatusHistory do
  subject { build(:appointment_status_history) }

  it { is_expected.to belong_to(:appointment) }
  it { is_expected.to validate_presence_of(:to_status) }
  it { is_expected.to validate_presence_of(:changed_at) }
end
