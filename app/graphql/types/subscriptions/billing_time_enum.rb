# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Subscriptions
    class BillingTimeEnum < Types::BaseEnum
      Subscription::BILLING_TIME.each do |type|
        value type
      end
    end
  end
end
