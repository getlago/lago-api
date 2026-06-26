# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Subscriptions
    class StatusTypeEnum < Types::BaseEnum
      Subscription::STATUSES.each do |type|
        value type
      end
    end
  end
end
