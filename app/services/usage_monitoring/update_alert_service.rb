# frozen_string_literal: true

module UsageMonitoring
  class UpdateAlertService < BaseService
    Result = BaseResult[:alert]

    def initialize(alert:, params:, billable_metric: nil)
      @alert = alert
      @params = params
      super
    end

    def call
      ActiveRecord::Base.transaction do
        alert.code = params[:code] if params.key?(:code)
        alert.billable_metric = billable_metric if billable_metric
        alert.save!

        # Updating threshold is hard deleting them all and recreating them
        if params[:thresholds].present?
          alert.thresholds.delete_all
          thresholds = params[:thresholds].map do |threshold|
            threshold.merge(organization_id: alert.organization_id)
          end
          alert.thresholds.create!(thresholds)
        end

        result.alert = alert
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
