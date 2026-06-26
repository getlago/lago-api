# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Subscriptions
    class ActivationRuleStatusEnum < Types::BaseEnum
      Subscription::ActivationRule::STATUSES.each_key do |status|
        value status
      end
    end
  end
end
