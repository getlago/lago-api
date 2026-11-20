# frozen_string_literal: true

module UsageMonitoring
  module CatalogWalletAlerts
    # Gives a contract wallet its own copy of the alert templates of the plan wallet it was copied from. A copy has
    # no observed value and no history: it is evaluated once the contract is active and its first credits are in.
    #
    # The caller reads the plan wallet under a FOR SHARE lock, as Contracts::MaterializeWalletsService does, and
    # preloads its alerts with their thresholds. Template writes lock the plan wallet first, so the copy is one
    # version of the templates, never a mix of two.
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
        # Only a wallet the caller has just inserted, so running the copy again never duplicates its alerts
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
