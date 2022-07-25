# frozen_string_literal: true

module Wallets
  class UpdateService < BaseService
    def update(**args)
      wallet = Wallet.find_by(id: args[:id])
      return result.fail!('not_found') unless wallet

      wallet.name = args[:name]
      wallet.expiration_date = args[:expiration_date]

      wallet.save!

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
