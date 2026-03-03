# frozen_string_literal: true

module UsageMonitoring
  class ProcessWalletAlertsJob < ApplicationJob
    queue_as :default

    unique :until_executed, on_conflict: :log

    def perform(wallet)
      ProcessWalletAlertsService.call!(wallet:)
    end
  end
end
