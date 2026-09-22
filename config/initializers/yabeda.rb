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

  # The wallet refresh lane: the consumer reports what a batch did with each customer, the refresh
  # service reports the wait it owns. No organization, customer or subscription id is ever a tag —
  # the series count has to stay a function of the reason list, not of the customer base.
  group :realtime_usage do
    counter :wallet_refresh_messages_total,
      comment: "Messages consumed from the realtime usage triggers topic",
      tags: %i[kind]

    counter :wallet_refresh_outcomes_total,
      comment: "Customers a consumed batch resolved to, by what the consumer did with them",
      tags: %i[outcome reason]

    # The prometheus adapter builds the exported name as group_name_unit, so the metrics are named
    # without the suffix their unit already adds.
    histogram :wallet_refresh_latency,
      comment: "Trigger watermark to the end of the refresh it caused",
      unit: :seconds,
      buckets: [0.5, 1, 2, 5, 10, 30, 60, 120, 300]

    histogram :wallet_refresh_duration,
      comment: "Time spent refreshing a customer's wallets, bucket wait excluded",
      unit: :seconds,
      buckets: [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10]

    histogram :wallet_refresh_bucket_wait,
      comment: "Time a refresh spent waiting for the usage buckets to reach the trigger watermark",
      unit: :seconds,
      buckets: [0.1, 0.25, 0.5, 1, 2, 5]
  end
end
