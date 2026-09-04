# frozen_string_literal: true

require "yabeda"

# https://github.com/yabeda-rb/yabeda-prometheus?tab=readme-ov-file#multi-process-server-support
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(
  dir: "/tmp/prometheus/"
)

Yabeda::Rails.config.ignore_actions = ["ApplicationController#health"]
Yabeda::Rails.config.buckets = [0.05, 0.1, 0.25, 0.5, 1, 5]

Yabeda.configure do
  default_tag :service, ENV["OTEL_SERVICE_NAME"] || "lago-api"
  default_tag :environment, Rails.env
  default_tag :version, ENV["LAGO_VERSION"] || "unknown"

  # Emitted only for organizations the realtime usage gate is on for, and only by
  # Events::Stores::Provider. No organization, subscription or charge id is ever a tag: the
  # series count has to stay a function of the reason list, not of the customer base.
  group :realtime_usage do
    counter :lookups_total,
      comment: "Current usage lookups answered from the pre-aggregated buckets or delegated to the events store",
      tags: %i[outcome reason]

    # The prometheus adapter builds the exported name as group_name_unit, so the metric is named
    # without the suffix its unit already adds.
    histogram :freshness,
      comment: "Age of the most recent bucket write backing a served computation",
      unit: :seconds,
      buckets: [30, 60, 120, 300, 600, 1800, 3600, 21_600]
  end
end
