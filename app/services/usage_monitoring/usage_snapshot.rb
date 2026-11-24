# frozen_string_literal: true

module UsageMonitoring
  # measured_at is read before the usage is built, so the usage holds at least the data ingested until then.
  UsageSnapshot = Data.define(:usage, :measured_at) do
    def self.measure
      measured_at = Time.current
      new(usage: yield, measured_at:)
    end
  end
end
