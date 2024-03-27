# frozen_string_literal: true

module Clock
  class TerminateWalletsJob < ApplicationJob
    include SentryConcern

    queue_as 'clock'

    def perform
      Wallet.active.expired.find_each do |wallet|
        Wallets::TerminateService.call(wallet:)
      end
    end
  end
end
