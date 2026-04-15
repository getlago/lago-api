# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class EvaluateService < BaseService
      Result = BaseResult[:rules]

      def initialize(subscription:)
        @subscription = subscription
        super
      end

      def call
        result.rules = []

        subscription.activation_rules.each do |rule|
          case rule
          when Subscription::ActivationRule::Payment
            Payment::EvaluateService.call!(rule:)
          end
          result.rules << rule
        end

        result
      end

      private

      attr_reader :subscription
    end
  end
end
