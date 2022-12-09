# frozen_string_literal: true

module Wallets
  class UpdateService < BaseService
    def update(wallet:, args:)
      return result.not_found_failure!(resource: 'wallet') unless wallet

      wallet.name = args[:name] if args.key?(:name)
      wallet.expiration_at = args[:expiration_at] if args.key?(:expiration_at)

      wallet.save!

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
