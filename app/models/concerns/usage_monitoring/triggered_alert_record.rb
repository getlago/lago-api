# frozen_string_literal: true

module UsageMonitoring
  module TriggeredAlertRecord
    extend ActiveSupport::Concern

    KINDS = {triggered: "triggered", resolved: "resolved", seeded: "seeded"}.freeze
    RESOLUTION_REASONS = {
      recovered: "recovered",
      threshold_updated: "threshold_updated",
      threshold_removed: "threshold_removed"
    }.freeze

    included do
      enum :kind, KINDS, validate: true
      enum :resolution_reason, RESOLUTION_REASONS, prefix: true, validate: {allow_nil: true}
    end
  end
end
