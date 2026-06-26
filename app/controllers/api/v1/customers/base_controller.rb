# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Api
  module V1
    module Customers
      class BaseController < Api::BaseController
        before_action :find_customer

        private

        attr_reader :customer

        def find_customer
          @customer = current_organization.customers.find_by!(external_id: params[:customer_external_id])
        rescue ActiveRecord::RecordNotFound
          not_found_error(resource: "customer")
        end
      end
    end
  end
end
