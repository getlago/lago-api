# frozen_string_literal: true

module Api
  module V2
    module Customers
      class BaseController < Api::V2::BaseController
        # These lists keep v1's offset pagination, so they keep its page checks.
        before_action :validate_pagination_params
        before_action :find_customer

        private

        attr_reader :customer

        def find_customer
          @customer = current_organization.customers.find_by(external_id: params[:customer_external_id])
          not_found_error(resource: "customer") unless customer
        end
      end
    end
  end
end
