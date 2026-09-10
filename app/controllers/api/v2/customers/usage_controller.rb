# frozen_string_literal: true

module Api
  module V2
    module Customers
      class UsageController < Api::BaseController
        include Api::RequiresProductCatalog

        def current
          customer = current_organization.customers.find_by(external_id: params[:customer_external_id])
          return not_found_error(resource: "customer") unless customer

          contract = customer.contracts.active.find_by(external_id: params[:external_contract_id])
          return method_not_allowed_error(code: "no_active_contract") unless contract

          result = ::Invoices::CustomerUsageService.call(
            customer:,
            billing_context: Billing::Context.from(contract:),
            apply_taxes: ActiveModel::Type::Boolean.new.cast(params.fetch(:apply_taxes, true)),
            usage_filters: UsageFilters.init_from_params(params)
          )

          if result.success?
            render(json: ::V2::Customers::UsageSerializer.new(result.usage, root_name: "customer_usage"))
          else
            render_error_response(result)
          end
        end

        private

        def resource_name
          "customer_usage"
        end
      end
    end
  end
end
