# frozen_string_literal: true

module Wallets
  module RecurringTransactionRules
    Result = BaseResult[:wallet, :payment_method]

    class UpdateService < BaseService
      def initialize(wallet:, params:)
        @wallet = wallet
        @params = params

        super
      end

      def call
        return result unless valid_payment_methods?

        created_recurring_rules_ids = []

        hash_recurring_rules.each do |payload_rule|
          lago_id = payload_rule[:lago_id]
          rule_attributes = payload_rule.except(:lago_id)
          # Normalize transaction_name to nil if empty
          rule_attributes[:transaction_name] = rule_attributes[:transaction_name].presence if rule_attributes.key?(:transaction_name)

          if rule_attributes.key?(:payment_method)
            rule_attributes[:payment_method_type] = rule_attributes[:payment_method][:payment_method_type] if rule_attributes[:payment_method].key?(:payment_method_type)
            rule_attributes[:payment_method_id] = rule_attributes[:payment_method][:payment_method_id] if rule_attributes[:payment_method].key?(:payment_method_id)
            rule_attributes.delete(:payment_method)
          end

          recurring_rule = wallet.recurring_transaction_rules.active.find_by(id: lago_id)

          if recurring_rule
            recurring_rule.update!(rule_attributes)
          else
            unless rule_attributes.key?(:invoice_requires_successful_payment)
              rule_attributes[:invoice_requires_successful_payment] = wallet.invoice_requires_successful_payment
            end

            created_recurring_rule = wallet.recurring_transaction_rules.create!(
              rule_attributes.merge(organization_id: wallet.organization_id)
            )

            created_recurring_rules_ids.push(created_recurring_rule.id)
          end
        end

        # NOTE: Delete recurring_rules that are no more linked to the wallet
        sanitize_recurring_rules(hash_recurring_rules, created_recurring_rules_ids)

        result.wallet = wallet
        result
      rescue BaseService::FailedResult => e
        e.result
      end

      private

      attr_reader :wallet, :params

      def sanitize_recurring_rules(args_recurring_rules, created_recurring_rules_ids)
        updated_recurring_rules_ids = args_recurring_rules.reject { |m| m[:lago_id].nil? }.map { |m| m[:lago_id] }
        not_needed_ids =
          wallet.recurring_transaction_rules.pluck(:id) - updated_recurring_rules_ids - created_recurring_rules_ids

        wallet.recurring_transaction_rules.where(id: not_needed_ids).find_each do |recurring_transaction_rule|
          Wallets::RecurringTransactionRules::TerminateService.call(recurring_transaction_rule:)
        end
      end

      def hash_recurring_rules
        @hash_recurring_rules ||= params.map { |m| m.to_h.deep_symbolize_keys }
      end

      def valid_payment_methods?
        hash_recurring_rules.each do |payload_rule|
          pm_result = BaseService::Result.new
          pm_result.payment_method = payment_method(payload_rule)

          unless PaymentMethods::ValidateService.new(pm_result, **payload_rule).valid?
            result.single_validation_failure!(field: :payment_method, error_code: "invalid_payment_method")

            return false
          end
        end

        true
      end

      def payment_method(rule_params)
        return nil if rule_params[:payment_method].blank? || rule_params[:payment_method][:payment_method_id].blank?

        PaymentMethod.find_by(id: rule_params[:payment_method][:payment_method_id], organization_id: wallet.organization_id)
      end
    end
  end
end
