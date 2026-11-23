# frozen_string_literal: true

module UsageMonitoring
  module CatalogWalletAlerts
    class CreateService < BaseService
      Result = BaseResult[:alert]

      def initialize(params:, plan_wallet: nil, catalog_wallet: nil)
        @wallet = plan_wallet || catalog_wallet
        @params = params.to_h.with_indifferent_access
        super
      end

      def call
        return result.not_found_failure!(resource: "wallet") unless wallet

        validate_single_values(params, %i[code name])
        return result unless result.success?

        if params[:alert_type].blank?
          return result.single_validation_failure!(field: :alert_type, error_code: "value_is_mandatory")
        end

        unless CatalogWalletAlertSettings::ALERT_TYPES.value?(params[:alert_type].to_s)
          return result.single_validation_failure!(field: :alert_type, error_code: "invalid_type")
        end

        validate_thresholds(params[:thresholds], params[:alert_type].to_s)
        return result unless result.success?

        ActiveRecord::Base.transaction do
          lock_wallet(wallet)
          return result unless result.success?

          alert = wallet.alerts.create!(organization:, alert_type: params[:alert_type].to_s, code: params[:code], name: params[:name])
          alert.thresholds.create!(prepare_thresholds(params[:thresholds], organization.id))

          # On an active contract the alert watches at once, without announcing the lines already past
          if wallet.is_a?(CatalogWallet) && wallet.contract.active?
            BaselineService.call!(catalog_wallet: wallet)
            alert.reload
          end

          result.alert = alert
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ActiveRecord::RecordNotUnique => e
        if TYPE_UNIQUE_INDEXES.include?(violated_unique_index(e))
          result.single_validation_failure!(field: :base, error_code: "alert_already_exists")
        else
          unique_index_failure!(e, CODE_UNIQUE_INDEXES)
        end
      end

      private

      attr_reader :wallet, :params

      delegate :organization, to: :wallet
    end
  end
end
