# frozen_string_literal: true

module UsageMonitoring
  module CatalogWalletAlerts
    # Deletes the alerts of the given wallets for good, inside the caller's transaction and locks. Their thresholds go
    # with them (ON DELETE CASCADE), and their history stays, since it keeps a copy of each alert's code, name and type.
    class DeleteAllService < BaseService
      Result = BaseResult

      # One wallet, a list or a relation of contract wallets or of plan wallet templates
      def initialize(catalog_wallets: nil, plan_wallets: nil)
        @catalog_wallets = catalog_wallets
        @plan_wallets = plan_wallets
        super
      end

      def call
        CatalogWalletAlert.where(catalog_wallet: catalog_wallets).delete_all unless catalog_wallets.nil?
        PlanWalletAlert.where(plan_wallet: plan_wallets).delete_all unless plan_wallets.nil?
        result
      end

      private

      attr_reader :catalog_wallets, :plan_wallets
    end
  end
end
