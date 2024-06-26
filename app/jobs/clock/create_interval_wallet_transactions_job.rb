# frozen_string_literal: true

module Clock
  class CreateIntervalWalletTransactionsJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'

    def perform
      Wallets::CreateIntervalWalletTransactionsService.call
    end
  end
end
