# frozen_string_literal: true

module Api
  module V2
    module Customers
      class BaseController < Api::V2::BaseController
        before_action :find_customer

        private

        def find_customer
          not_found_error(resource: "customer") unless customer
        end

        def customer
          @customer ||= current_organization.customers.find_by(external_id: params[:customer_external_id])
        end
      end
    end
  end
end
