# frozen_string_literal: true

module Wallets
  class UpdateService < BaseService
    def update(wallet:, args:)
      return result.not_found_failure!(resource: "wallet") unless wallet
      return result unless valid_expiration_at?(expiration_at: args[:expiration_at])
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

    def valid_expiration_at?(expiration_at:)
      return true if expiration_at.blank?

      if Utils::DatetimeService.valid_format?(expiration_at)
        parsed_expiration_at = if expiration_at.is_a?(String)
          DateTime.strptime(expiration_at)
        else
          expiration_at
        end

        return true if parsed_expiration_at.to_date > Time.current.to_date
      end

      result.single_validation_failure!(field: :expiration_at, error_code: "invalid_date")

      false
    end
  end
end
