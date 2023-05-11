# frozen_string_literal: true

module Api
  module V1
    module Customers
      class AppliedTaxRatesController < Api::BaseController
        def create
          return not_found_error(resource: 'customer') unless customer

          tax_rate = current_organization.tax_rates.find_by(code: input_params[:tax_rate_code])
          return not_found_error(resource: 'tax_rate') unless tax_rate

          result = ::AppliedTaxRates::CreateService.call(customer:, tax_rate:)
          if result.success?
            render(json: ::V1::AppliedTaxRateSerializer.new(result.applied_tax_rate, root_name: 'applied_tax_rate'))
          else
            render_error_response(result)
          end
        end

        def destroy
          return not_found_error(resource: 'customer') unless customer

          tax_rate = current_organization.tax_rates.find_by(code: params[:tax_rate_code])
          return not_found_error(resource: 'tax_rate') unless tax_rate

          applied_tax_rate = customer.applied_tax_rates.find_by(customer:, tax_rate:)
          return not_found_error(resource: 'applied_tax_rate') unless applied_tax_rate

          result = ::AppliedTaxRates::DestroyService.call(applied_tax_rate:)
          if result.success?
            render(json: ::V1::AppliedTaxRateSerializer.new(result.applied_tax_rate, root_name: 'applied_tax_rate'))
          else
            render_error_response(result)
          end
        end

        private

        def customer
          @customer ||= current_organization.customers.find_by(external_id: params[:customer_external_id])
        end

        def input_params
          params.require(:applied_tax_rate).permit(:tax_rate_code)
        end
      end
    end
  end
end
