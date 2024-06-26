# frozen_string_literal: true

module Wallets
  class RefreshOngoingBalanceJob < ApplicationJob
    queue_as 'wallets'

    unique :until_executed

    def perform(wallet)
      Wallets::Balance::RefreshOngoingService.call(wallet:)
    end
  end
end
