# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class ApplyService < BaseService
      def initialize(subscription:, activation_rules:)
        @subscription = subscription
        @activation_rules = activation_rules

        super
      end

      def call
        return result if activation_rules.nil?

        subscription.activation_rules.destroy_all

        return result if activation_rules.empty?

        activation_rules.each do |rule_params|
          attrs = {
            organization_id: subscription.organization_id,
            type: rule_params[:type],
            status: :inactive
          }
          attrs[:timeout_hours] = rule_params[:timeout_hours] if rule_params.key?(:timeout_hours)

          subscription.activation_rules.create!(attrs)
        end

        result
      end

      private

      attr_reader :subscription, :activation_rules
    end
  end
end
