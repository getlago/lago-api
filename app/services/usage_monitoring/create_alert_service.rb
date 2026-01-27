# frozen_string_literal: true

module UsageMonitoring
  class CreateAlertService < BaseService
    include ::UsageMonitoring::Concerns::CreateOrUpdateConcern

    Result = BaseResult[:alert]

    def initialize(organization:, alertable:, params:)
      @organization = organization
      @alertable = alertable
      @params = params
      super
    end

    def call
      if params[:alert_type].blank?
        return result.single_validation_failure!(field: :alert_type, error_code: "value_is_mandatory")
      end

      unless Alert::STI_MAPPING.key?(params[:alert_type])
        return result.single_validation_failure!(field: :alert_type, error_code: "invalid_type")
      end

      if alertable.is_a?(Wallet) && !Alert::WALLET_TYPES.include?(params[:alert_type])
        return result.single_validation_failure!(field: :alert_type, error_code: "invalid_for_wallet")
      end

      if alertable.is_a?(Subscription) && Alert::WALLET_TYPES.include?(params[:alert_type])
        return result.single_validation_failure!(field: :alert_type, error_code: "invalid_for_subscription")
      end

      if params[:alert_type] == "lifetime_usage_amount" && !organization.using_lifetime_usage?
        return result.single_validation_failure!(field: :alert_type, error_code: "feature_not_available")
      end

      if params[:thresholds].blank?
        return result.single_validation_failure!(field: :thresholds, error_code: "value_is_mandatory")
      end

      if params[:thresholds].size > AlertThreshold::SOFT_LIMIT
        return result.single_validation_failure!(field: :thresholds, error_code: "too_many_thresholds")
      end

      threshold_values = params[:thresholds].map { |t| t[:value] }.compact
      if threshold_values.size != threshold_values.uniq.size
        return result.single_validation_failure!(field: :thresholds, error_code: "duplicate_threshold_values")
      end

      billable_metric = find_billable_metric_from_params!
      return result unless result.success?

      ActiveRecord::Base.transaction do
        alert = Alert.create!(
          organization:,
          subscription_external_id: subscription&.external_id,
          wallet: wallet,
          billable_metric:,
          alert_type: params[:alert_type].to_s,
          name: params[:name],
          code: params[:code]
        )

        alert.thresholds.create!(prepare_thresholds(params[:thresholds], organization.id))

        result.alert = alert
      end

      result
    rescue KeyError
      result.single_validation_failure!(field: "alert_type", error_code: "invalid_type")
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      if e.message.include?("idx_alerts_code_unique_per_subscription") || e.message.include?("idx_alerts_code_unique_per_wallet")
        result.single_validation_failure!(field: :code, error_code: "value_already_exist")
      else
        # Only one alert per [alert_type, billable_metric] pair is allowed.
        result.single_validation_failure!(field: :base, error_code: "alert_already_exists")
      end
    end

    private

    attr_reader :organization, :alertable, :params

    def subscription
      alertable if alertable.is_a?(Subscription)
    end

    def wallet
      alertable if alertable.is_a?(Wallet)
    end
  end
end
