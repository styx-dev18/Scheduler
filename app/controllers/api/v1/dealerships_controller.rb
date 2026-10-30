module Api
  module V1
    class DealershipsController < BaseController
      def index
        page = params[:page]
        payload = Rails.cache.fetch([ "dealerships", "index", page ], expires_in: 5.minutes) do
          pagy, records = pagy(Dealership.includes(:opening_hours).order(:name, :id))
          { data: DealershipSerializer.new(records).serializable_hash, meta: pagination_meta(pagy) }
        end
        render_success(payload[:data], meta: payload[:meta])
      end
    end
  end
end
