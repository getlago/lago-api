# frozen_string_literal: true

module Types
  module Subscriptions
    class CancelationReasonEnum < Types::BaseEnum
      Subscription::CANCELATION_REASONS.each_key do |reason|
        value reason
      end
    end
  end
end
