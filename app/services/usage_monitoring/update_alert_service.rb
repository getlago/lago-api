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
        alert.recurring_threshold = params[:recurring_threshold] if params.key?(:recurring_threshold)
        alert.billable_metric = billable_metric if billable_metric
        alert.save!

        # Updating threshold is hard deleting them all and recreating them
        if params[:thresholds].present?
          alert.thresholds.delete_all
          thresholds = params[:thresholds].map do |threshold|
            threshold.to_h.merge(organization_id: alert.organization_id)
          end
          alert.thresholds.create!(thresholds)
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
