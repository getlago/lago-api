# frozen_string_literal: true

module UsageMonitoring
  class DispatchCatalogWalletAlertsService < BaseService
    Result = BaseResult

    def initialize(catalog_wallet:)
      @catalog_wallet = catalog_wallet
      super
    end

    def call
      return result unless License.premium?

      # Evaluation reads the balance back from the database, so it must not run before the commit
      after_commit { ProcessCatalogWalletAlertsJob.perform_later(catalog_wallet) if catalog_wallet.alerts.exists? }

      result
    end

    private

    attr_reader :catalog_wallet
  end
end
