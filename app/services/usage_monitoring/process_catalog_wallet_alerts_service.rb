# frozen_string_literal: true

module UsageMonitoring
  class ProcessCatalogWalletAlertsService < BaseService
    Result = BaseResult

    def initialize(catalog_wallet:)
      @catalog_wallet = catalog_wallet
      super
    end

    def call
      catalog_wallet.reload
      catalog_wallet.alerts.order(:id).each { evaluate(it) } if watched?

      result
    end

    private

    attr_reader :catalog_wallet

    # Read without a lock: a termination deletes the alerts under its contract lock, and an alert deleted while its
    # evaluation waits is skipped
    def watched?
      catalog_wallet.contract.active? && !catalog_wallet.terminated_at?
    end

    def evaluate(alert)
      if alert.previous_value.nil?
        log_missing_baseline(alert) if baseline_due?(alert)
      else
        ProcessAlertService.call!(alert:, alertable: catalog_wallet, current_metrics: catalog_wallet)
      end
    rescue ActiveRecord::RecordNotFound => e
      # Deleted since it was loaded: its lock no longer finds it
      raise unless e.model == alert.class.name
    end

    # A balance alert takes its baseline once the wallet holds money, an ongoing balance one at activation even at 0,
    # so one still missing then means a missed hook. Taken late, it would swallow the first crossing.
    def baseline_due?(alert)
      catalog_wallet.funded? || alert.ongoing_balance?
    end

    def log_missing_baseline(alert)
      Rails.logger.warn(
        "[alerts] catalog wallet alert without a baseline alert_id=#{alert.id} catalog_wallet_id=#{catalog_wallet.id}"
      )
    end
  end
end
