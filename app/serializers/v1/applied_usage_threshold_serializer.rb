# frozen_string_literal: true

module V1
  class AppliedUsageThresholdSerializer < ModelSerializer
    def serialize
      payload = {
        lifetime_usage_amount_cents: model.lifetime_usage_amount_cents,
        created_at: model.created_at.iso8601
      }

      payload.merge!(usage_treshold)
      payload
    end

    private

    def usage_treshold
      {
        usage_threshold: ::V1::UsageThresholdSerializer.new(model.usage_threshold).serialize
      }
    end
  end
end
