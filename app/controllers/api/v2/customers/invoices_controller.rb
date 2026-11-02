# frozen_string_literal: true

module Api
  module V2
    module Customers
      class InvoicesController < Api::V2::BaseController
        include Api::V2::InvoiceIndex

        # A list only: nothing on it expands.
        serializable_with ::V2::InvoiceSerializer, expand_on: []

        def index
          customer = current_organization.customers.find_by(external_id: params[:customer_external_id])
          return not_found_error(resource: "customer") unless customer

          invoice_index(customer:)
        end

        private

        def resource_name
          "invoice"
        end
      end
    end
  end
end
