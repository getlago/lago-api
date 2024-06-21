# frozen_string_literal: true

module Api
  module V1
    module Analytics
      class OverdueBalancesController < BaseController
        def index
          @result = ::Analytics::OverdueBalancesService.new(current_organization, **filters).call

          super
        end

        private

        def filters
          {
            external_customer_id: params[:external_customer_id],
            currency: params[:currency]&.upcase,
            months: params[:months]
          }
        end
      end
    end
  end
end
