# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Subscriptions
    class NextSubscriptionTypeEnum < Types::BaseEnum
      value "upgrade"
      value "downgrade"
    end
  end
end
