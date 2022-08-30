# frozen_string_literal: true

module Wallets
  class UpdateService < BaseService
    def update(**args)
      wallet = Wallet.find_by(id: args[:id])
      return result.fail!(code: 'not_found') unless wallet

      wallet.name = args[:name] if args.key?(:name)
      wallet.expiration_date = args[:expiration_date] if args.key?(:expiration_date)

      wallet.save!

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
