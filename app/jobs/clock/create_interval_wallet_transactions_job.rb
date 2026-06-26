# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Clock
  class CreateIntervalWalletTransactionsJob < ClockJob
    def perform
      Wallets::CreateIntervalWalletTransactionsService.call
    end
  end
end
