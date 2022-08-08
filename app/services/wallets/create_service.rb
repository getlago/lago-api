# frozen_string_literal: true

module Wallets
  class CreateService < BaseService
    def create(**args)
      return result unless valid?(**args)

      wallet = Wallet.create!(
        customer_id: args[:customer_id],
        name: args[:name],
        rate_amount: args[:rate_amount],
        expiration_date: args[:expiration_date],
        status: :active,
      )

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    def valid?(**args)
      Wallets::ValidateService.new(result, **args).valid?
    end
  end
end
