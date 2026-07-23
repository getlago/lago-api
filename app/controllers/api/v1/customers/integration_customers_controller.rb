# frozen_string_literal: true

module Api
  module V1
    module Customers
      class IntegrationCustomersController < BaseController
        def set_as_default
          integration_customer = customer.integration_customers.find_by(code: params[:code])
          return not_found_error(resource: "integration_customer") unless integration_customer

          result = ::IntegrationCustomers::SetAsDefaultService.call(integration_customer:)
          if result.success?
            render_integration_customer(result.integration_customer)
          else
            render_error_response(result)
          end
        end

        private

        def resource_name
          "customer"
        end

        def render_integration_customer(integration_customer)
          render(
            json: ::V1::IntegrationCustomerSerializer.new(
              integration_customer,
              root_name: "integration_customer"
            )
          )
        end
      end
    end
  end
end
