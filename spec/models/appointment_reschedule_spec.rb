require "rails_helper"

RSpec.describe AppointmentReschedule do
  subject { build(:appointment_reschedule) }

  it { is_expected.to belong_to(:appointment) }
  it { is_expected.to validate_presence_of(:prev_start_at) }
  it { is_expected.to validate_presence_of(:prev_end_at) }
  it { is_expected.to validate_presence_of(:new_start_at) }
  it { is_expected.to validate_presence_of(:new_end_at) }

  it "has a valid factory" do
    expect(build(:appointment_reschedule)).to be_valid
  end

  it "rejects a previous interval that ends at its start" do
    record = build(:appointment_reschedule, prev_end_at: Time.utc(2030, 1, 7, 9))

    expect(record).not_to be_valid
    expect(record.errors[:prev_end_at]).to eq([ "must be after prev_start_at" ])
  end

  it "rejects a new interval that ends before its start" do
    record = build(:appointment_reschedule, new_end_at: Time.utc(2030, 1, 7, 9))

    expect(record).not_to be_valid
    expect(record.errors[:new_end_at]).to eq([ "must be after new_start_at" ])
  end

  describe "database" do
    it "enforces the previous interval check constraint" do
      record = create(:appointment_reschedule)

      expect { record.update_columns(prev_end_at: record.prev_start_at) }
        .to raise_error(ActiveRecord::StatementInvalid, /appointment_reschedules_prev_end_after_start_check/)
    end

    it "enforces the new interval check constraint" do
      record = create(:appointment_reschedule)

      expect { record.update_columns(new_end_at: record.new_start_at) }
        .to raise_error(ActiveRecord::StatementInvalid, /appointment_reschedules_new_end_after_start_check/)
    end
  end
end
