# frozen_string_literal: true

module Wallets
  module RecurringTransactionRules
    class CreateService < BaseService
      def initialize(wallet:, wallet_params:)
        @wallet = wallet
        @wallet_params = wallet_params

        super
      end

      def call
        return unless License.premium?

        if method == 'fixed' && rule_params[:paid_credits].nil? && rule_params[:granted_credits].nil?
          paid_credits = wallet_params[:paid_credits]
          granted_credits = wallet_params[:granted_credits]
        end

        rule = wallet.recurring_transaction_rules.create!(
          paid_credits: rule_params[:paid_credits] || paid_credits || 0.0,
          granted_credits: rule_params[:granted_credits] || granted_credits || 0.0,
          threshold_credits: rule_params[:threshold_credits] || 0.0,
          interval: rule_params[:interval],
          method:,
          started_at: rule_params[:started_at],
          target_ongoing_balance: rule_params[:target_ongoing_balance],
          trigger: rule_params[:trigger].to_s
        )

        result.recurring_transaction_rule = rule
        result
      end

      private

      attr_reader :wallet, :wallet_params

      def rule_params
        @rule_params ||= wallet_params[:recurring_transaction_rules].first
      end

      def method
        @method ||= rule_params[:method] || 'fixed'
      end
    end
  end
end
