# frozen_string_literal: true

module UsageMonitoring
  class UpdateAlertService < BaseService
    include Concerns::CreateOrUpdateConcern

    Result = BaseResult[:alert]

    def initialize(alert:, params:)
      @alert = alert
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: "alert") unless alert

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
    end

    private

    attr_reader :alert, :params
    delegate :organization, to: :alert
  end
end
