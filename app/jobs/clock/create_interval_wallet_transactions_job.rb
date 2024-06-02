# frozen_string_literal: true

module Clock
  class CreateIntervalWalletTransactionsJob < ApplicationJob
    queue_as 'clock'

    def perform
      Wallets::CreateIntervalWalletTransactionsService.call
    end
  end
end
