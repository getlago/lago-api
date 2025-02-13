# frozen_string_literal: true

module Clock
  class CreateIntervalWalletTransactionsJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      else
        :clock
      end
    end

    def perform
      Wallets::CreateIntervalWalletTransactionsService.call
    end
  end
end
