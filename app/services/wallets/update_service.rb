# frozen_string_literal: true

module Wallets
  class UpdateService < BaseService
    def initialize(wallet:, params:)
      @wallet = wallet
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "wallet") unless wallet
      return result unless valid_expiration_at?(expiration_at: params[:expiration_at])
      return result unless valid_recurring_transaction_rules?

      ActiveRecord::Base.transaction do
        wallet.name = params[:name] if params.key?(:name)
        wallet.expiration_at = params[:expiration_at] if params.key?(:expiration_at)
        if params.key?(:invoice_requires_successful_payment)
          wallet.invoice_requires_successful_payment = ActiveModel::Type::Boolean.new.cast(params[:invoice_requires_successful_payment])
        end
        if params[:recurring_transaction_rules] && License.premium?
          Wallets::RecurringTransactionRules::UpdateService.call(wallet:, params: params[:recurring_transaction_rules])
        end

        wallet.save!
      end

      SendWebhookJob.perform_later("wallet.updated", wallet)
      Wallets::Balance::RefreshOngoingService.call(wallet: wallet.reload)

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
      return true if Validators::ExpirationDateValidator.valid?(expiration_at)

      result.single_validation_failure!(field: :expiration_at, error_code: "invalid_date")
      false
    end
  end
end
