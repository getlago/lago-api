# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Clock
  class TerminateWalletsJob < ClockJob
    def perform
      Wallet.active.expired.find_each do |wallet|
        Wallets::TerminateService.call(wallet:)
      end
    end
  end
end
