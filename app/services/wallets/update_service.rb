# frozen_string_literal: true

module Wallets
  class UpdateService < BaseService
    def initialize(wallet:, params:)
      @wallet = wallet
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: 'wallet') unless wallet
      return result unless valid_expiration_at?(expiration_at: params[:expiration_at])
      return result unless valid_recurring_transaction_rules?

      ActiveRecord::Base.transaction do
        wallet.name = params[:name] if params.key?(:name)
        wallet.expiration_at = params[:expiration_at] if params.key?(:expiration_at)

        if params[:recurring_transaction_rules] && License.premium?
          Wallets::RecurringTransactionRules::UpdateService.call(wallet:, params: params[:recurring_transaction_rules])
        end

        wallet.save!
      end

      Wallets::Balance::RefreshOngoingService.call(wallet:)

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :wallet, :params

    def valid_recurring_transaction_rules?
      Wallets::ValidateRecurringTransactionRulesService.new(result, **params).valid?
    end

    def valid_expiration_at?(expiration_at:)
      return true if expiration_at.blank?

      if Utils::Datetime.valid_format?(expiration_at)
        parsed_expiration_at = if expiration_at.is_a?(String)
          DateTime.strptime(expiration_at)
        else
          expiration_at
        end

        return true if parsed_expiration_at.to_date > Time.current.to_date
      end

      result.single_validation_failure!(field: :expiration_at, error_code: 'invalid_date')

      false
    end
  end
end
