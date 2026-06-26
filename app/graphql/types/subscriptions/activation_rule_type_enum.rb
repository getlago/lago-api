# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Subscriptions
    class ActivationRuleTypeEnum < Types::BaseEnum
      Subscription::ActivationRule::TYPES.each_key do |type|
        value type
      end
    end
  end
end
