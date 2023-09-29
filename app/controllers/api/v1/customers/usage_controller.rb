# frozen_string_literal: true

module Api
  module V1
    module Customers
      class UsageController < Api::BaseController
        def current
          service = ::Invoices::CustomerUsageService
            .new(
              nil,
              customer_id: params[:customer_external_id],
              subscription_id: params[:external_subscription_id],
              organization_id: current_organization.id,
            )
          result = service.usage

          if result.success?
            render(
              json: ::V1::Customers::UsageSerializer.new(
                result.usage,
                root_name: 'customer_usage',
                includes: %i[charges_usage],
              ),
            )
          else
            render_error_response(result)
          end
        end
      end
    end
  end
end
