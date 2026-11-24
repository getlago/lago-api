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

        templates = plan_wallet.alerts.sort_by { [it.created_at, it.id] }
        return result if templates.empty?

        result.alerts = insert_alerts(templates)
        insert_thresholds(templates, result.alerts.index_by(&:code))
        result
      end

      private

      attr_reader :plan_wallet, :catalog_wallet

      delegate :organization, to: :catalog_wallet

      # One statement per table, since the copy runs under the customer's billing lock. The templates passed the same
      # validations. Each copy is dated a microsecond after the previous one, so the copies keep the templates' order.
      def insert_alerts(templates)
        now = Time.current
        rows = templates.each_with_index.map do |template, index|
          created_at = now + (index / 1_000_000.0)
          {organization_id: organization.id, catalog_wallet_id: catalog_wallet.id, created_at:, updated_at: created_at, **template.attributes.slice(*ALERT_ATTRIBUTES)}
        end

        CatalogWalletAlert.insert_all!(rows, returning: CatalogWalletAlert.column_names) # rubocop:disable Rails/SkipsModelValidations
          .map { CatalogWalletAlert.instantiate(it) }
          .sort_by { [it.created_at, it.id] }
      end

      def insert_thresholds(templates, alerts_by_code)
        now = Time.current
        rows = templates.flat_map do |template|
          alert_id = alerts_by_code.fetch(template.code).id
          template.thresholds.map do |threshold|
            {organization_id: organization.id, catalog_wallet_alert_id: alert_id, created_at: now, updated_at: now, **threshold.attributes.slice(*THRESHOLD_ATTRIBUTES)}
          end
        end

        CatalogWalletAlertThreshold.insert_all!(rows) if rows.any? # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
