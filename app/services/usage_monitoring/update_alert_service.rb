# frozen_string_literal: true

module UsageMonitoring
  class UpdateAlertService < BaseService
    include ::UsageMonitoring::Concerns::CreateOrUpdateConcern

    Result = BaseResult[:alert]

    def initialize(alert:, params:)
      @alert = alert
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: "alert") unless alert

      if params.has_key?(:thresholds) && params[:thresholds].size > AlertThreshold::SOFT_LIMIT
        return result.single_validation_failure!(field: :thresholds, error_code: "too_many_thresholds")
      end

      if params[:thresholds].present?
        threshold_values = params[:thresholds].map { |t| t[:value] }.compact
        if threshold_values.size != threshold_values.uniq.size
          return result.single_validation_failure!(field: :thresholds, error_code: "duplicate_threshold_values")
        end
      end

      result.alert = alert

      billable_metric = find_billable_metric_from_params!
      return result unless result.success?

      ActiveRecord::Base.transaction do
        alert.name = params[:name] if params.key?(:name)
        alert.code = params[:code] if params.key?(:code)
        alert.billable_metric = billable_metric if billable_metric
        alert.save!

        if params[:thresholds].present?
          alert.thresholds.delete_all
          alert.thresholds.create!(prepare_thresholds(params[:thresholds], alert.organization_id))
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      if e.message.include?("idx_alerts_code_unique_per_subscription")
        result.single_validation_failure!(field: :code, error_code: "value_already_exist")
      else
        # Only one alert per [alert_type, billable_metric] pair is allowed.
        result.single_validation_failure!(field: :base, error_code: "alert_already_exists")
      end
    end

    private

    attr_reader :alert, :params
    delegate :organization, to: :alert
  end
end
