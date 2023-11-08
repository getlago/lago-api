# frozen_string_literal: true

module Api
  module V1
    module Analytics
      class GrossRevenuesController < Api::BaseController
        def index
          result = ::Analytics::GrossRevenue.find_all_by(current_organization.id, **filters)

          render(
            json: ::CollectionSerializer.new(
              result,
              ::V1::Analytics::GrossRevenueSerializer,
              collection_name: 'gross_revenues',
            ),
          )
        end

        private

        def filters
          {
            external_customer_id: params[:external_customer_id],
            currency: params[:currency].upcase,
            months: params[:months].to_i,
          }
        end
      end
    end
  end
end
