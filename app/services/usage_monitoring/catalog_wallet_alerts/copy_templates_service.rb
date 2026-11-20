# frozen_string_literal: true

module UsageMonitoring
  module CatalogWalletAlerts
    # The caller holds a FOR SHARE lock on the plan wallet and preloads its alerts with their thresholds: template
    # writes lock the plan wallet first, so a copy never mixes two versions of a template.
    class CopyTemplatesService < BaseService
      Result = BaseResult[:alerts]

      ALERT_ATTRIBUTES = %w[alert_type code name].freeze
      THRESHOLD_ATTRIBUTES = %w[code value recurring notify_on].freeze

      def initialize(plan_wallet:, catalog_wallet:)
        @plan_wallet = plan_wallet
        @catalog_wallet = catalog_wallet
        super
      end

      def call
        result.alerts = []
        # Only onto a wallet the caller has just inserted: a wallet read back from the database keeps its own alerts
        return result unless catalog_wallet.previously_new_record?

        result.alerts = plan_wallet.alerts.sort_by { [it.created_at, it.id] }.map { copy(it) }
        result
      end

      private

      attr_reader :plan_wallet, :catalog_wallet

      delegate :organization, to: :catalog_wallet

      def copy(template)
        alert = catalog_wallet.alerts.create!(organization:, **template.attributes.slice(*ALERT_ATTRIBUTES))
        alert.thresholds.create!(template.thresholds.map { {organization:, **it.attributes.slice(*THRESHOLD_ATTRIBUTES)} })
        alert
      end
    end
  end
end
