# frozen_string_literal: true

module Queries
  class OrdersQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:status).maybe do
        value(:string, included_in?: Order::STATUSES.keys.map(&:to_s)) |
          array(:string, included_in?: Order::STATUSES.keys.map(&:to_s))
      end
      optional(:order_type).maybe do
        value(:string, included_in?: Order::ORDER_TYPES.keys.map(&:to_s)) |
          array(:string, included_in?: Order::ORDER_TYPES.keys.map(&:to_s))
      end
      optional(:external_customer_id).maybe(:string)
    end
  end
end
