# frozen_string_literal: true

module Api
  module V1
    module Analytics
      class OutstandingInvoicesController < BaseController
        def index
          @result = ::Analytics::OutstandingInvoicesService.new(current_organization, **filters).call

          super
        end

        private

        def filters
          {
            currency: params[:currency]&.upcase,
            months: params[:months].to_i,
          }
        end
      end
    end
  end
end
