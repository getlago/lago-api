# frozen_string_literal: true

module UsageMonitoring
  module CatalogWalletAlerts
    # Starts the wallet's alerts that have no baseline, seeding the opted-in lines already in alarm so nothing announces
    # them. An empty wallet starts only its ongoing balance alerts, unseeded: at 0 every balance line would be in alarm.
    class BaselineService < BaseService
      include ::UsageMonitoring::Concerns::CreateOrUpdateConcern

      Result = BaseResult[:alerts]

      def initialize(catalog_wallet:)
        @catalog_wallet = catalog_wallet
        super
      end

      def call
        ActiveRecord::Base.transaction do
          # Holds off balance changes, so the next evaluation starts from the value taken here
          catalog_wallet.lock!("FOR NO KEY UPDATE")
          funded = catalog_wallet.funded?

          waiting = catalog_wallet.alerts.where(previous_value: nil).order(:id).lock.includes(:thresholds)
          result.alerts = waiting.filter_map { start(it, funded) }
        end

        result
      end

      private

      attr_reader :catalog_wallet

      def start(alert, funded)
        return unless funded || alert.ongoing_balance?

        alert.update!(previous_value: alert.find_value(catalog_wallet), last_processed_at: Time.current)
        seed_alarms_already_past(alert, catalog_wallet) if funded
        alert
      end
    end
  end
end
