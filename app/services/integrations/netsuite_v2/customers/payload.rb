# frozen_string_literal: true

module Integrations
  module NetsuiteV2
    module Customers
      class Payload
        def initialize(customer:, integration_customer:)
          @customer = customer
          @integration_customer = integration_customer
        end

        def to_h
          ::V1::CustomerSerialize.new(customer).serialize
        end

        private

        attr_reader :customer, :integration_customer
      end
    end
  end
end
