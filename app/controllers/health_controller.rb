class HealthController < Api::V1::BaseController
  def show
    render_success({ status: "ok" })
  end

  def ready
    ActiveRecord::Base.connection.execute("SELECT 1")
    if ActiveRecord::Base.connection_pool.migration_context.needs_migration?
      return render_failure("SERVICE_UNAVAILABLE", detail: "Pending migrations")
    end

    render_success({ status: "ok" })
  rescue ActiveRecord::ActiveRecordError
    render_failure("SERVICE_UNAVAILABLE", detail: "Database unavailable")
  end
end
