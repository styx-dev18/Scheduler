require "rails_helper"

RSpec.describe Appointment, "lifecycle" do
  let(:at) { Time.utc(2030, 1, 7, 9, 5) }

  it "AC10 complete! on a confirmed appointment raises and writes nothing" do
    appointment = create(:appointment)

    expect { appointment.complete!(at:, actor: "staff") }
      .to raise_error(Scheduling::StatusMachine::InvalidTransition, "confirmed -> completed")
    expect(appointment.reload.status).to eq("confirmed")
    expect(appointment.status_histories.count).to eq(0)
  end

  it "AC10 start! moves to in_progress and records history" do
    appointment = create(:appointment)

    expect(appointment.start!(at:, actor: "staff")).to equal(appointment)
    expect(appointment.reload.status).to eq("in_progress")
    expect(appointment.status_histories.pluck(:from_status, :to_status, :changed_at, :actor))
      .to eq([ [ "confirmed", "in_progress", at, "staff" ] ])
  end

  it "AC10 complete! follows start!" do
    appointment = create(:appointment)
    appointment.start!(at:, actor: "staff")

    appointment.complete!(at: at + 1.hour, actor: "staff")

    expect(appointment.reload.status).to eq("completed")
    expect(appointment.status_histories.count).to eq(2)
  end

  it "AC10 mark_no_show! moves a confirmed appointment to no_show" do
    appointment = create(:appointment)

    appointment.mark_no_show!(at:, actor: "staff")

    expect(appointment.reload.status).to eq("no_show")
  end

  it "AC10 cancel! stores cancelled_at, reason and history" do
    appointment = create(:appointment)

    appointment.cancel!(at:, actor: "customer", reason: "ac10 reason")

    appointment.reload
    expect(appointment.status).to eq("cancelled")
    expect(appointment.cancelled_at).to eq(at)
    expect(appointment.cancellation_reason).to eq("ac10 reason")
    expect(appointment.status_histories.pluck(:from_status, :to_status, :actor))
      .to eq([ %w[confirmed cancelled customer] ])
  end

  it "AC10 cancel! allows a nil reason" do
    appointment = create(:appointment)

    appointment.cancel!(at:, actor: "customer")

    expect(appointment.reload.cancellation_reason).to be_nil
  end

  it "AC10 cancel! on a completed appointment raises and changes nothing" do
    appointment = create(:appointment, status: "completed")

    expect { appointment.cancel!(at:, actor: "customer") }
      .to raise_error(Scheduling::StatusMachine::InvalidTransition)
    expect(appointment.reload.cancelled_at).to be_nil
    expect(appointment.status_histories.count).to eq(0)
  end

  it "AC10 rolls back the status when the history row cannot be written" do
    appointment = create(:appointment)

    expect { appointment.start!(at: nil, actor: "staff") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(appointment.reload.status).to eq("confirmed")
  end

  it "EC3 validates cancellation_reason length" do
    appointment = build(:appointment, cancellation_reason: "a" * 501)

    expect(appointment).not_to be_valid
    expect(appointment.errors[:cancellation_reason]).to be_present
    appointment.cancellation_reason = "a" * 500
    expect(appointment).to be_valid
  end

  it "AC10 destroys reschedules with the appointment" do
    reschedule = create(:appointment_reschedule)

    expect { reschedule.appointment.destroy }.to change(AppointmentReschedule, :count).by(-1)
  end
end
