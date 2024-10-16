# frozen_string_literal: true

module Wallets
  class RefreshOngoingBalanceJob < ApplicationJob
    queue_as 'wallets'

    unique :until_executed, on_conflict: :log

    retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 6

    def perform(wallet)
      return unless wallet.ready_to_be_refreshed?

      Wallets::Balance::RefreshOngoingService.call(wallet:)
    end
  end
end
