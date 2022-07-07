# frozen_string_literal: true

module Api
  module V1
    class CustomersController < Api::BaseController
      def create
        service = Customers::CreateService.new
        result = service.create_from_api(
          organization: current_organization,
          params: create_params,
        )

        if result.success?
          render(
            json: ::V1::CustomerSerializer.new(
              result.customer,
              root_name: 'customer',
            ),
          )
        else
          validation_errors(result)
        end
      end

      def current_usage
        service = Invoices::CustomerUsageService
          .new(nil, customer_id: params[:customer_id], organization_id: current_organization.id)
        result = service.usage

        if result.success?
          render(
            json: ::V1::CustomerUsageSerializer.new(
              result.usage,
              root_name: 'customer_usage',
              includes: %i[charges_usage],
            ),
          )
        else
          render_error_response(result)
        end
      end

      private

      def create_params
        params.require(:customer).permit(
          :customer_id,
          :name,
          :country,
          :address_line1,
          :address_line2,
          :state,
          :zipcode,
          :email,
          :city,
          :url,
          :phone,
          :logo_url,
          :legal_name,
          :legal_number,
          :vat_rate,
          billing_configuration: [:payment_provider, :provider_customer_id, :sync],
        )
      end
    end
  end
end
