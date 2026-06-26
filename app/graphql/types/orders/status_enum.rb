# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Orders
    class StatusEnum < Types::BaseEnum
      graphql_name "OrderStatusEnum"

      Order::STATUSES.each_key do |type|
        value type
      end
    end
  end
end
