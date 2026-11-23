# frozen_string_literal: true

module UsageMonitoring
  module CatalogWalletAlerts
    class CreateService < BaseService
      Result = BaseResult[:alert]

      def initialize(plan_wallet:, params:)
        @plan_wallet = plan_wallet
        @params = params.to_h.with_indifferent_access
        super
      end

      def call
        return result.not_found_failure!(resource: "plan_wallet") unless plan_wallet

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

        # Template writes lock the plan wallet, so a contract copying its templates sees one version of them
        plan_wallet.with_lock do
          return result.not_found_failure!(resource: "plan_wallet") if plan_wallet.discarded?

          alert = plan_wallet.alerts.create!(organization:, alert_type: params[:alert_type].to_s, code: params[:code], name: params[:name])
          alert.thresholds.create!(prepare_thresholds(params[:thresholds], organization.id))

          result.alert = alert
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ActiveRecord::RecordNotUnique => e
        if violated_unique_index(e) == "idx_plan_wallet_alerts_alert_type_unique"
          result.single_validation_failure!(field: :base, error_code: "alert_already_exists")
        else
          unique_index_failure!(e, "idx_plan_wallet_alerts_code_unique" => :code)
        end
      end

      private

      attr_reader :plan_wallet, :params

      delegate :organization, to: :plan_wallet
    end
  end
end
