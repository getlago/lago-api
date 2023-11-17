# frozen_string_literal: true

module Api
  module V1
    module Analytics
      class GrossRevenuesController < BaseController
        def index
          @result = ::Analytics::GrossRevenuesService.new(current_organization, **filters).call

          super
        end

        private

        def filters
          {
            external_customer_id: params[:external_customer_id],
            currency: params[:currency]&.upcase,
            months: params[:months].to_i,
          }
        end
      end
    end
  end
end
