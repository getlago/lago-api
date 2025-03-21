# frozen_string_literal: true

module Clock
  class CreateIntervalWalletTransactionsJob < ApplicationJob
    if ENV["SENTRY_DSN"].present? && ENV["SENTRY_ENABLE_CRONS"].present?
      include SentryCronConcern
    end

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
