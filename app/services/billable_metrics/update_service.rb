# frozen_string_literal: true

module BillableMetrics
  class UpdateService < BaseService
    def initialize(billable_metric:, params:)
      @billable_metric = billable_metric
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: 'billable_metric') unless billable_metric

      billable_metric.name = params[:name] if params.key?(:name)
      billable_metric.description = params[:description] if params.key?(:description)

      # NOTE: Only name and description are editable if billable metric
      #       is attached to a plan
      unless billable_metric.plans.exists?
        billable_metric.code = params[:code] if params.key?(:code)
        billable_metric.aggregation_type = params[:aggregation_type]&.to_sym if params.key?(:aggregation_type)
        billable_metric.field_name = params[:field_name] if params.key?(:field_name)

        if params.key?(:group)
          group_result = update_groups(billable_metric, params[:group])
          return group_result if group_result.error
        end
      end

      billable_metric.save!

      result.billable_metric = billable_metric
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :billable_metric, :params

    def update_groups(metric, group_params)
      ActiveRecord::Base.transaction do
        metric.groups.each(&:inactive!)

        Groups::CreateBatchService.call(
          billable_metric: metric,
          group_params: group_params.with_indifferent_access,
        )
      end
    end
  end
end
