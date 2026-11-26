# frozen_string_literal: true

module UsageMonitoring
  class ProcessCatalogWalletAlertsService < BaseService
    Result = BaseResult

    def initialize(catalog_wallet:)
      @catalog_wallet = catalog_wallet
      super
    end

    def call
      ActiveRecord::Base.transaction do
        # Held until the evaluation commits, so a termination committed after this check cannot let an alert fire
        contract = catalog_wallet.contract
        contract.lock!("FOR SHARE")
        next unless contract.active?

        catalog_wallet.reload
        next if catalog_wallet.terminated_at?

        catalog_wallet.alerts.order(:id).each { evaluate(it) }
      end

      result
    end

    private

    attr_reader :catalog_wallet

    def evaluate(alert)
      # A baseline is taken once the wallet holds money, so a funded wallet without one means a missed hook.
      # Taken late, it would swallow the first crossing.
      if alert.previous_value.nil?
        log_missing_baseline(alert) if catalog_wallet.funded?
        return
      end

      ProcessAlertService.call!(alert:, alertable: catalog_wallet, current_metrics: catalog_wallet)
    rescue ActiveRecord::RecordNotFound => e
      # Deleted since it was loaded: its lock no longer finds it
      raise unless e.model == alert.class.name
    end

    def log_missing_baseline(alert)
      Rails.logger.warn(
        "[alerts] catalog wallet alert without a baseline alert_id=#{alert.id} catalog_wallet_id=#{catalog_wallet.id}"
      )
    end
  end
end
