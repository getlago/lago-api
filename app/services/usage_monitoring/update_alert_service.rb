# frozen_string_literal: true

module UsageMonitoring
  class UpdateAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(alert:, params:, billable_metric: nil)
      @alert = alert
      @params = params
      @billable_metric = billable_metric
      super
    end

    def call
      result.alert = alert

      # NOTE: If the billable_metric isn't already set, it means it's not a BillableMetric*Alert
      if billable_metric && alert.billable_metric.nil?
        return result.single_validation_failure!(field: :billable_metric, error_code: "invalid_alert_type")
      end

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
      result
    end

    private

    attr_reader :alert, :params, :billable_metric
  end
end
