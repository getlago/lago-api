# frozen_string_literal: true

module Api
  module V1
    module Customers
      class AppliedTaxesController < Api::BaseController
        def create
          return not_found_error(resource: 'customer') unless customer

          tax = current_organization.taxes.find_by(code: input_params[:tax_code])
          return not_found_error(resource: 'tax') unless tax

          result = ::Customers::AppliedTaxes::CreateService.call(customer:, tax:)
          if result.success?
            render(json: ::V1::Customers::AppliedTaxSerializer.new(result.applied_tax, root_name: 'applied_tax'))
          else
            render_error_response(result)
          end
        end

        def destroy
          return not_found_error(resource: 'customer') unless customer

          tax = current_organization.taxes.find_by(code: params[:tax_code])
          return not_found_error(resource: 'tax') unless tax

          applied_tax = customer.applied_taxes.find_by(customer:, tax:)
          return not_found_error(resource: 'applied_tax') unless applied_tax

          result = ::Customers::AppliedTaxes::DestroyService.call(applied_tax:)
          if result.success?
            render(json: ::V1::Customers::AppliedTaxSerializer.new(result.applied_tax, root_name: 'applied_tax'))
          else
            render_error_response(result)
          end
        end

        private

        def customer
          @customer ||= current_organization.customers.find_by(external_id: params[:customer_external_id])
        end

        def input_params
          params.require(:applied_tax).permit(:tax_code)
        end
      end
    end
  end
end
