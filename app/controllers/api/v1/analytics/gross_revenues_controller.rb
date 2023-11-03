# frozen_string_literal: true

module Api
  module V1
    module Analytics
      class GrossRevenueController < Api::BaseController
        def index
          result = ::Analytics::GrossRevenue.find_all_by(current_organization.id, **filters)

          render(
            json: ::CollectionSerializer.new(
              result,
              ::V1::Analytics::GrossRevenueSerializer,
              collection_name: 'gross_revenue',
            ),
          )
        end

        private

        def filters
          {
            external_customer_id: params[:customer_external_id],
            currency: params[:currency],
          }
        end
      end
    end
  end
end
