module Api
  module V1
    class ServiceTypesController < BaseController
      def index
        dealership_id = params[:dealership_id].presence
        payload = Rails.cache.fetch([ "service_types", "index", dealership_id, params[:page] ], expires_in: 5.minutes) do
          pagy, records = pagy(scope(dealership_id))
          { data: ServiceTypeSerializer.new(records).serializable_hash, meta: pagination_meta(pagy) }
        end
        render_success(payload[:data], meta: payload[:meta])
      end

      private

      def scope(dealership_id)
        service_types = ServiceType.order(:name, :id)
        return service_types unless dealership_id

        service_types.where(id: DealershipServiceType.where(dealership_id: dealership_id).select(:service_type_id))
      end
    end
  end
end
