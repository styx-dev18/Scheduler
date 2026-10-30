require "rails_helper"
require "rake"

RSpec.describe "scheduler:load_data" do
  let(:dealership_id) { "00000000-0000-4000-9000-000000000001" }

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("scheduler:load_data")
  end

  def run_task
    task = Rake::Task["scheduler:load_data"]
    task.reenable
    task.invoke("200")
  end

  def counts
    [ Appointment.where(dealership_id:).count, ServiceBay.where(dealership_id:).count, Technician.where(dealership_id:).count ]
  end

  it "AC14 loads the data set and is repeatable" do
    run_task
    expect(counts).to eq([ 200, 20, 20 ])
    expect(Dealership.find(dealership_id).name).to eq("Load Test Motors")

    expect { run_task }.not_to raise_error
    expect(counts).to eq([ 200, 20, 20 ])
  end
end
