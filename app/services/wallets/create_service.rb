# frozen_string_literal: true

module Wallets
  class CreateService < BaseService
    def initialize(params:)
      @params = params
      super
    end

    def call
<<<<<<< HEAD
      return result unless valid?
=======
      return result unless valid?(**params)
>>>>>>> 62c2da89 (feat(wallet): Add granted and paid credits on recurring transaction rule)

      wallet = Wallet.new(
        customer_id: result.current_customer.id,
        name: params[:name],
        rate_amount: params[:rate_amount],
        expiration_at: params[:expiration_at],
        status: :active
      )

      ActiveRecord::Base.transaction do
        currency_result = Customers::UpdateService.new(nil).update_currency(
          customer: result.current_customer,
          currency: params[:currency]
        )
        return currency_result unless currency_result.success?

        wallet.currency = wallet.customer.currency
        wallet.save!

        if params[:recurring_transaction_rules]
          Wallets::RecurringTransactionRules::CreateService.call(wallet:, wallet_params: params)
        end
      end

      result.wallet = wallet

      WalletTransactions::CreateJob.perform_later(
        organization_id: params[:organization_id],
        params: {
          wallet_id: wallet.id,
          paid_credits: params[:paid_credits],
          granted_credits: params[:granted_credits],
          source: :manual
        }
      )

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :params

<<<<<<< HEAD
    def valid?
=======
    def valid?(**params)
>>>>>>> 62c2da89 (feat(wallet): Add granted and paid credits on recurring transaction rule)
      Wallets::ValidateService.new(result, **params).valid?
    end
  end
end
