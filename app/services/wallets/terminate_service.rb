# frozen_string_literal: true

module Wallets
  class TerminateService < BaseService
    def terminate(id)
      wallet = Wallet.find_by(id: id)
      return result.not_found_failure!(resource: 'wallet') unless wallet

      wallet.mark_as_terminated! if wallet.active?

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def terminate_all_expired
      Wallet.active.expired.find_each(&:mark_as_terminated!)
    end
  end
end
