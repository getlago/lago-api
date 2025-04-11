# frozen_string_literal: true

module Clock
  class CreateIntervalWalletTransactionsJob < ClockJob
    def perform
      Wallets::CreateIntervalWalletTransactionsService.call
    end
  end
end
