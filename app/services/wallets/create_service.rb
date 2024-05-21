# frozen_string_literal: true

module Wallets
  class CreateService < BaseService
    def create(args)
      return result unless valid?(**args)

      wallet = Wallet.new(
        customer_id: result.current_customer.id,
        name: args[:name],
        rate_amount: args[:rate_amount],
        expiration_at: args[:expiration_at],
        status: :active,
      )

      ActiveRecord::Base.transaction do
        currency_result = Customers::UpdateService.new(nil).update_currency(
          customer: result.current_customer,
          currency: args[:currency],
        )
        return currency_result unless currency_result.success?

        wallet.currency = wallet.customer.currency
        wallet.save!

        if args[:recurring_transaction_rules] && License.premium?
          create_recurring_transaction_rule(
            recurring_transaction_rules: args[:recurring_transaction_rules],
            paid_credits: args[:paid_credits],
            granted_credits: args[:granted_credits],
            wallet:,
          )
        end
      end

      result.wallet = wallet

      WalletTransactions::CreateJob.perform_later(
        organization_id: args[:organization_id],
        params: {
          wallet_id: wallet.id,
          paid_credits: args[:paid_credits],
          granted_credits: args[:granted_credits],
          source: :manual
        },
      )

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def valid?(**args)
      Wallets::ValidateService.new(result, **args).valid?
    end

    def create_recurring_transaction_rule(recurring_transaction_rules:, paid_credits:, granted_credits:, wallet:)
      recurring_rule = recurring_transaction_rules.first

      RecurringTransactionRule.create!(
        wallet:,
        paid_credits:,
        granted_credits:,
        threshold_credits: recurring_rule[:threshold_credits] || '0.0',
        interval: recurring_rule[:interval],
        method: recurring_rule[:method] || 'fixed',
        trigger: recurring_rule[:trigger].to_s
      )
    end
  end
end
