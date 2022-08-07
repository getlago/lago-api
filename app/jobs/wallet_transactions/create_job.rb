# frozen_string_literal: true

module WalletTransactions
  class CreateJob < ApplicationJob
    queue_as 'wallets'

    def perform(wallet_id, paid_credits, granted_credits)
      result = WalletTransactions::CreateService.new(
        wallet_id: wallet_id,
        paid_credits: paid_credits,
        granted_credits: granted_credits,
      ).create

      raise result.throw_error unless result.success?
    end
  end
end
