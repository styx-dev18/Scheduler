require "rails_helper"

RSpec.describe Appointment do
  subject(:appointment) { create(:appointment) }

  it { is_expected.to belong_to(:customer) }
  it { is_expected.to belong_to(:vehicle) }
  it { is_expected.to belong_to(:technician) }
  it { is_expected.to belong_to(:service_bay) }
  it { is_expected.to belong_to(:service_type) }
  it { is_expected.to belong_to(:dealership) }
  it { is_expected.to have_many(:status_histories).class_name("AppointmentStatusHistory").dependent(:destroy) }
  it { is_expected.to validate_presence_of(:start_at) }
  it { is_expected.to validate_presence_of(:end_at) }
  it { is_expected.to define_enum_for(:status).with_values(
    confirmed: "confirmed", in_progress: "in_progress", completed: "completed", cancelled: "cancelled", no_show: "no_show"
  ).backed_by_column_of_type(:string).validating }

  it "AC5 rejects an end that is not after the start" do
    appointment.end_at = appointment.start_at
    expect(appointment).not_to be_valid
    expect(appointment.errors[:end_at]).to be_present
  end

  it "AC5 rejects a technician from another dealership" do
    appointment.technician = create(:technician)
    expect(appointment).not_to be_valid
    expect(appointment.errors[:technician]).to be_present
  end

  it "AC5 rejects a bay from another dealership" do
    appointment.service_bay = create(:service_bay)
    expect(appointment).not_to be_valid
    expect(appointment.errors[:service_bay]).to be_present
  end

  it "AC5 rejects an unknown status" do
    appointment.status = "bogus"
    expect(appointment).not_to be_valid
  end

  describe "database" do
    let(:saved) { create(:appointment) }

    it "AC4 generates time_range as [start_at, end_at)" do
      range = saved.reload.time_range
      expect([ range.begin, range.end, range.exclude_end? ]).to eq([ saved.start_at, saved.end_at, true ])
    end

    it "AC4 treats time_range as read-only" do
      original = saved.time_range
      expect { saved.update!(time_range: Time.utc(2031, 1, 1)..Time.utc(2031, 1, 2)) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect(saved.reload.time_range).to eq(original)
    end

    it "AC4 rejects end_at <= start_at at the database level" do
      saved
      expect do
        saved.update_columns(end_at: saved.start_at)
      end.to raise_error(ActiveRecord::StatementInvalid, /appointments_end_after_start_check/)
    end

    it "AC4 rejects an invalid status at the database level" do
      saved
      expect do
        saved.update_columns(status: "bogus")
      end.to raise_error(ActiveRecord::StatementInvalid, /appointments_status_check/)
    end
  end
end
