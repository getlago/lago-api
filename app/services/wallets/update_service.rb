# frozen_string_literal: true

module Wallets
  class UpdateService < BaseService
    def update(wallet:, args:)
      return result.not_found_failure!(resource: 'wallet') unless wallet
      return result unless valid_recurring_transaction_rules?(**args)

      ActiveRecord::Base.transaction do
        wallet.name = args[:name] if args.key?(:name)
        wallet.expiration_at = args[:expiration_at] if args.key?(:expiration_at)

        if args[:recurring_transaction_rules] && License.premium?
          Wallets::RecurringTransactionRules::UpdateService.call(wallet:, params: args[:recurring_transaction_rules])
        end

        wallet.save!
      end

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def valid_recurring_transaction_rules?(**args)
      Wallets::ValidateRecurringTransactionRulesService.new(result, **args).valid?
    end
  end
end
