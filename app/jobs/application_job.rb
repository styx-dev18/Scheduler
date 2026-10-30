class ApplicationJob < ActiveJob::Base
  attr_accessor :request_id

  def serialize
    super.merge("request_id" => request_id || Current.request_id)
  end

  def deserialize(job_data)
    super
    self.request_id = job_data["request_id"]
  end

  around_perform do |job, block|
    previous = Current.request_id
    Current.request_id = job.request_id if job.request_id
    block.call
  ensure
    Current.request_id = previous
  end
end
