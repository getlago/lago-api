# frozen_string_literal: true

module UsageMonitoring
  class UpdateAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(alert:, params:)
      @alert = alert
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: "alert") unless alert

      result.alert = alert

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
    end

    private

    attr_reader :alert, :params

    def billable_metric
      @billable_metric ||= if params[:billable_metric_id]
        BillableMetric.find_by(id: params[:billable_metric_id])
      elsif params[:billable_metric_code]
        BillableMetric.find_by(code: params[:billable_metric_code])
      end
    end
  end
end
