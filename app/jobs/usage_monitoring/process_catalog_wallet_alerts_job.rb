# frozen_string_literal: true

module UsageMonitoring
  class ProcessCatalogWalletAlertsJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ALERTS"])
        :alerts_high_priority
      else
        :default
      end
    end

    unique :until_executed, on_conflict: :log

    def perform(catalog_wallet)
      return unless License.premium?

      ProcessCatalogWalletAlertsService.call!(catalog_wallet:)
    end
  end
end
