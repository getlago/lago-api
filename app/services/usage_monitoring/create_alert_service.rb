# frozen_string_literal: true

module UsageMonitoring
  class CreateAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(organization:, subscription:, params:)
      @organization = organization
      @subscription = subscription
      @params = params
      super
    end

    def call
      if params[:thresholds].blank?
        return result.single_validation_failure!(field: :thresholds, error_code: "value_is_mandatory")
      end

      if params[:thresholds].size > AlertThreshold::SOFT_LIMIT
        return result.single_validation_failure!(field: :thresholds, error_code: "too_many_thresholds")
      end

      ActiveRecord::Base.transaction do
        alert = Alert.create!(
          organization: organization,
          subscription_external_id: subscription.external_id,
          billable_metric: billable_metric,
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
      if e.message.include?("idx_alerts_code_unique_per_subscription")
        result.single_validation_failure!(field: :code, error_code: "value_already_exists")
      else
        # Only one alert per [alert_type, billable_metric] pair is allowed.
        result.single_validation_failure!(field: :base, error_code: "alert_already_exists")
      end
    end

    private

    attr_reader :organization, :subscription, :params

    def billable_metric
      @billable_metric ||= if params[:billable_metric]
        params[:billable_metric]
      elsif params[:billable_metric_id]
        BillableMetric.find_by(id: params[:billable_metric_id])
      elsif params[:billable_metric_code]
        BillableMetric.find_by(code: params[:billable_metric_code])
      end
    end
  end
end
