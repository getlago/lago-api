# frozen_string_literal: true

module Clock
  class RefreshWalletsOngoingBalanceJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'

    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      jobs = []
      batch_size = 100

      Wallet.active.select(:id).find_each do |wallet|
        jobs << Wallets::RefreshOngoingBalanceJob.new(wallet)

        if jobs.size >= batch_size
          ActiveJob.perform_all_later(jobs)
          jobs = []
        end
      end

      ActiveJob.perform_all_later(jobs)
    end
  end
end
