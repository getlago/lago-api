# frozen_string_literal: true

module V2
  module Customers
    class UsageSerializer < V1::Customers::UsageSerializer
      def serialize
        super.merge(products_usage: ProductUsageSerializer.new(model.fees).serialize)
      end
    end
  end
end
