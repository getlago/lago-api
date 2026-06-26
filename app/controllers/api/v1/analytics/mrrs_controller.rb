# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Api
  module V1
    module Analytics
      class MrrsController < BaseController
        def index
          @result = ::Analytics::MrrsService.call(current_organization, **filters)

          super
        end

        private

        def filters
          {
            currency: params[:currency]&.upcase,
            months: params[:months],
            billing_entity_id: billing_entity&.id
          }
        end
      end
    end
  end
end
