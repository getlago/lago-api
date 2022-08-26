# frozen_string_literal: true

module Api
  module V1
    class AppliedAddOnsController < Api::BaseController
      def create
        service = AppliedAddOns::CreateService.new
        result = service.create_from_api(
          organization: current_organization,
          args: create_params,
        )

        if result.success?
          render(
            json: ::V1::AppliedAddOnSerializer.new(
              result.applied_add_on,
              root_name: 'applied_add_on',
            ),
          )
        else
          validation_errors(result)
        end
      end

      private

      def create_params
        params.require(:applied_add_on).permit(
          :external_customer_id,
          :add_on_code,
          :amount_cents,
          :amount_currency,
        )
      end
    end
  end
end
