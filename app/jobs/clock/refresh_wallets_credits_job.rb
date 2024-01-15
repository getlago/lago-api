# frozen_string_literal: true

module Clock
  class RefreshWalletsCreditsJob < ApplicationJob
    queue_as 'clock'

    def perform
      Wallet
        .active
        .joins(customer: :organization)
        .merge(Organization.credits_auto_refreshed)
        .find_each do |wallet|
          Wallets::RefreshCreditsJob.perform_later(wallet)
        end
    end
  end
end
