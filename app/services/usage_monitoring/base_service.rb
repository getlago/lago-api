# frozen_string_literal: true

module UsageMonitoring
  class BaseService < ::BaseService
    private

    def prepare_thresholds(thresholds, organization_id)
      thresholds.map do |threshold_params|
        row = {
          organization_id:,
          code: nil,
          recurring: false
        }.merge(threshold_params.to_h).with_indifferent_access

        # An explicit null would break the NOT NULL column, so let its default stand instead
        row.delete(:notify_on) if row[:notify_on].nil?
        row
      end
    end
  end
end
