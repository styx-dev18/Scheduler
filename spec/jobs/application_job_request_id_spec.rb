require "rails_helper"

RSpec.describe ApplicationJob do
  let(:job_class) do
    Class.new(described_class) do
      cattr_accessor :seen

      def self.name = "RequestIdProbeJob"

      def perform
        self.class.seen = Current.request_id
      end
    end
  end

  before { stub_const("RequestIdProbeJob", job_class) }

  after { Current.reset }

  it "AC1 serializes the enqueuing request_id" do
    Current.request_id = "req-enqueue"

    expect(job_class.new.serialize["request_id"]).to eq("req-enqueue")
  end

  it "AC1 restores the request_id on deserialize and exposes it during perform" do
    data = job_class.new.tap { |j| j.request_id = "req-from-web" }.serialize

    job = job_class.new
    job.deserialize(data)
    job.perform_now

    expect(job_class.seen).to eq("req-from-web")
  end

  it "AC1 restores the previous Current.request_id after perform" do
    job = job_class.new
    job.request_id = "req-inner"
    Current.request_id = "req-outer"

    job.perform_now

    expect(Current.request_id).to eq("req-outer")
  end

  it "EC1 restores the previous Current.request_id when perform raises" do
    failing = Class.new(described_class) do
      def self.name = "FailingProbeJob"
      def perform = raise(ArgumentError, "boom")
    end
    job = failing.new
    job.request_id = "req-inner"
    Current.request_id = "req-outer"

    expect { job.perform_now }.to raise_error(ArgumentError)
    expect(Current.request_id).to eq("req-outer")
  end

  it "EC1 leaves Current.request_id untouched when the job has none" do
    Current.request_id = "req-outer"
    job = job_class.new

    job.perform_now

    expect(job_class.seen).to eq("req-outer")
  end
end
