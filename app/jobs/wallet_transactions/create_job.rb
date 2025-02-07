# frozen_string_literal: true

module WalletTransactions
  class CreateJob < ApplicationJob
    queue_as 'high_priority'

    def perform(organization_id:, params:, new_wallet: false)
      organization = Organization.find(organization_id)
      WalletTransactions::CreateService.call!(organization:, params:)

      if new_wallet
        SendWebhookJob.perform_later('wallet.created', Wallet.find_by(id: params[:wallet_id]))
      end
    end
  end
end
