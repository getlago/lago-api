# frozen_string_literal: true

module UsageMonitoring
  module ThresholdRecord
    extend ActiveSupport::Concern

    SOFT_LIMIT = 20
    NOTIFY_ON_TRIGGERED = "triggered"
    NOTIFY_ON_RESOLVED = "resolved"
    NOTIFY_ON_VALUES = [NOTIFY_ON_TRIGGERED, NOTIFY_ON_RESOLVED].freeze

    included do
      # notify_on is a set: duplicates are dropped and the values kept in one order, whatever order was sent
      normalizes :notify_on, with: ->(values) { NOTIFY_ON_VALUES & values }
    end

    def notify_on_resolved?
      notify_on.include?(NOTIFY_ON_RESOLVED)
    end
  end
end
