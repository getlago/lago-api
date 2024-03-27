# frozen_string_literal: true

module WalletTransactions
  class CreateJob < ApplicationJob
    queue_as "wallets"

    def perform(organization_id:, wallet_id:, paid_credits:, granted_credits:, source:)
      WalletTransactions::CreateService.new.create(
        organization_id:,
        wallet_id:,
        paid_credits:,
        granted_credits:,
        source:
      )
    end
  end
end
