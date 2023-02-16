# frozen_string_literal: true

module Api
  module V1
    class AppliedAddOnsController < Api::BaseController
      def create
        customer = Customer.find_by(
          external_id: create_params[:external_customer_id],
          organization_id: current_organization.id,
        )

        add_on = AddOn.find_by(
          code: create_params[:add_on_code],
          organization_id: current_organization.id,
        )

        result = AppliedAddOns::CreateService.call(customer:, add_on:, params: create_params)

        if result.success?
          render(
            json: ::V1::AppliedAddOnSerializer.new(
              result.applied_add_on,
              root_name: 'applied_add_on',
            ),
          )
        else
          render_error_response(result)
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
