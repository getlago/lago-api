# frozen_string_literal: true

module Api
  module V1
    module Customers
      class PaymentMethodsController < BaseController
        include PaymentMethodIndex

        def index
          payment_method_index(external_customer_id: customer.external_id)
        end

        private

        def resource_name
          "payment_method"
        end
      end
    end
  end
end
