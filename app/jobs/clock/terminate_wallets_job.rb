# frozen_string_literal: true

module Clock
  class TerminateWalletsJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      else
        :clock
      end
    end

    def perform
      Wallet.active.expired.find_each do |wallet|
        Wallets::TerminateService.call(wallet:)
      end
    end
  end
end
