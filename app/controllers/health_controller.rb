class HealthController < Api::V1::BaseController
  def show
    render_success({ status: "ok" })
  end
end
