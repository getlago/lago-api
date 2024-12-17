# frozen_string_literal: true

module Clock
  class RefreshWalletsOngoingBalanceJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_CLOCK'])
        :clock
      else
        :default
      end
    end

    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      Wallet.active.ready_to_be_refreshed.find_each do |wallet|
        Wallets::RefreshOngoingBalanceJob.perform_later(wallet)
      end
    end
  end
end
