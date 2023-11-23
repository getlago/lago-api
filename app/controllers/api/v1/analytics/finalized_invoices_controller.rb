# frozen_string_literal: true

module Api
  module V1
    module Analytics
      class FinalizedInvoicesController < BaseController
        def index
          @result = ::Analytics::FinalizedInvoicesService.new(current_organization, **filters).call

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
