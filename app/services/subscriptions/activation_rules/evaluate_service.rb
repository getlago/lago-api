# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class EvaluateService < BaseService
      def initialize(subscription:)
        @subscription = subscription
        super
      end

      def call
        subscription.activation_rules.each do |rule|
          case rule
          when Subscription::ActivationRule::Payment
            Payment::EvaluateService.call!(rule:)
          end
        end

        result
      end

      private

      attr_reader :subscription
    end
  end
end
