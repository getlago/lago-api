# frozen_string_literal: true

module Clock
  class CreateIntervalWalletTransactionsJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Wallets::CreateIntervalWalletTransactionsService.call
    end
  end
end
