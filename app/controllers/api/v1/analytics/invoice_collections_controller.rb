# frozen_string_literal: true

module Api
  module V1
    module Analytics
      class InvoiceCollectionsController < BaseController
        def index
          @result = ::Analytics::InvoiceCollectionsService.new(current_organization, **filters).call

          super
        end

        private

        def filters
          {
            currency: params[:currency]&.upcase,
            months: params[:months]
          }
        end
      end
    end
  end
end
