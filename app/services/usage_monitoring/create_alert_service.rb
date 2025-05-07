# frozen_string_literal: true

module UsageMonitoring
  class CreateAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(organization:, subscription:, params:, billable_metric: nil)
      @organization = organization
      @subscription = subscription
      @params = params
      @billable_metric = billable_metric
      super
    end

    def call
      unless subscription.active?
        return result.single_validation_failure!(field: :status, error_code: "subscription_must_be_active")
      end

      if params[:thresholds].blank?
        return result.single_validation_failure!(field: :thresholds, error_code: "thresholds_must_be_present")
      end

      if params[:code].blank?
        return result.single_validation_failure!(field: :code, error_code: "code_must_be_present")
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
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
      result
    rescue ActiveRecord::NotNullViolation => e
      result.validation_failure!(errors: e.message)
      result
    end

    private

    attr_reader :organization, :subscription, :params, :billable_metric
  end
end
