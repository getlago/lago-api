# frozen_string_literal: true

module Wallets
  class RefreshOngoingBalanceJob < ApplicationJob
    queue_as 'wallets'

    unique :while_executing, on_conflict: :log

    def perform(wallet)
      # If the wallet was updated recently, it's probably because this same job was executed
      # Since it runs every 5.minutes, even if the was was modified for other reasons and
      # the balance wasn't updated, it will be updated in the next run.
      return if wallet.updated_at < 1.minute.ago

      Wallets::Balance::RefreshOngoingService.call(wallet:)
    end
  end
end
