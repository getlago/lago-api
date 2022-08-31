# frozen_string_literal: true

module WalletTransactions
  class CreateJob < ApplicationJob
    queue_as 'wallets'

    def perform(organization_id:, wallet_id:, paid_credits:, granted_credits:)
      WalletTransactions::CreateService.new.create(
        organization_id: organization_id,
        wallet_id: wallet_id,
        paid_credits: paid_credits,
        granted_credits: granted_credits,
      )
    end
  end
end
