# frozen_string_literal: true

module Wallets
  class CreateService < BaseService
    def create(**args)
      return result unless valid?(**args)

      wallet = Wallet.create!(
        customer_id: result.current_customer.id,
        name: args[:name],
        rate_amount: args[:rate_amount],
        expiration_date: args[:expiration_date],
        status: :active,
      )

      result.wallet = wallet

      WalletTransactions::CreateJob.perform_later(
        organization_id: args[:organization_id],
        wallet_id: wallet.id,
        paid_credits: args[:paid_credits],
        granted_credits: args[:granted_credits],
      )

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def valid?(**args)
      Wallets::ValidateService.new(result, **args).valid?
    end
  end
end
