# frozen_string_literal: true

module Api
  module V1
    module Analytics
      class InvoicedUsagesController < BaseController
        def index
          @result = ::Analytics::InvoicedUsagesService.new(current_organization, **filters).call

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
