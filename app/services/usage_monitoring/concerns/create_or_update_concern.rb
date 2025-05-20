# frozen_string_literal: true

module UsageMonitoring
  module Concerns
    module CreateOrUpdateConcern
      extend ActiveSupport::Concern

      def find_billable_metric_from_params!
        if params[:billable_metric]
          params[:billable_metric]
        elsif params[:billable_metric_id]
          organization.billable_metrics.find_by!(id: params[:billable_metric_id])
        elsif params[:billable_metric_code]
          organization.billable_metrics.find_by!(code: params[:billable_metric_code])
        end
      rescue ActiveRecord::RecordNotFound
        result.not_found_failure!(resource: "billable_metric")
      end
    end
  end
end
