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
      [:code, :alert_type, :thresholds].each do |field|
        if params[field].blank?
          return result.single_validation_failure!(field:, error_code: "#{field}_must_be_present")
        end
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
    rescue ActiveRecord::RecordInvalid, ActiveRecord::NotNullViolation => e
      result.validation_failure!(errors: e.message)
    rescue ActiveRecord::RecordNotUnique => e
      if e.message.include?("idx_alerts_code_unique_per_subscription")
        result.single_validation_failure!(field: :code, error_code: "code_already_exists")
      else
        result.validation_failure!(errors: e.message)
      end
    end

    private

    attr_reader :organization, :subscription, :params, :billable_metric
  end
end
