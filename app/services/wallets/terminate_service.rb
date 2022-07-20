# frozen_string_literal: true

module Wallets
  class TerminateService < BaseService
    def terminate(id)
      wallet = Wallet.find_by(id: id)
      return result.fail!('not_found') unless wallet

      wallet.mark_as_terminated! unless wallet.terminated?

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    def terminate_all_expired
      # TODO
    end
  end
end
