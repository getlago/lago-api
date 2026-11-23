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

  # The realtime usage lanes: the wallet refresh consumer reports what a batch did with each customer,
  # and the bucket wait is reported per lane. No organization, customer or subscription id is ever a tag —
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

    histogram :bucket_wait,
      comment: "Time a lane spent waiting for the usage buckets to reach the trigger watermark",
      unit: :seconds,
      tags: %i[lane],
      buckets: [0.1, 0.25, 0.5, 1, 2, 5]
  end

  # The wallet alerts lane: how a moved balance reached evaluation, and what the consumer did with
  # it, then the usage alerts lane. Like the refresh lane, no organization, wallet or subscription id is ever a tag.
  group :usage_monitoring do
    counter :wallet_alerts_dispatched_total,
      comment: "Wallets handed to alert evaluation, by the way they were sent (kafka, job, job_fallback)",
      tags: %i[via]

    counter :wallet_alerts_outcomes_total,
      comment: "Wallets a consumed batch resolved to, by what the consumer did with them",
      tags: %i[outcome reason]

    histogram :wallet_alerts_latency,
      comment: "Dispatch of a moved balance to the end of its alert evaluation",
      unit: :seconds,
      buckets: [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30]

    counter :usage_alerts_outcomes_total,
      comment: "Subscriptions a consumed realtime usage triggers batch resolved to, by what the usage alerts consumer did with them",
      tags: %i[outcome reason]

    histogram :usage_alerts_latency,
      comment: "Trigger watermark to the end of the usage alerts evaluation it caused",
      unit: :seconds,
      buckets: [0.5, 1, 2, 5, 10, 30, 60, 120, 300]

    histogram :usage_alerts_evaluation_duration,
      comment: "Time spent evaluating a subscription's usage alerts, bucket wait excluded",
      unit: :seconds,
      buckets: [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10]
  end

  # Raw topic events copied to the shadow organization of a billing engine migration. Like the
  # other lanes, no organization or subscription id is ever a tag.
  group :billing_engine_migrations do
    counter :events_copy_total,
      comment: "Events of migrated organizations read from the raw topic, by what the copy did with them (copied, unmapped, invalid)",
      tags: %i[outcome]

    counter :events_copy_failures_total,
      comment: "Raw topic batches whose copy raised and will be retried"

    histogram :events_copy_lag,
      comment: "Age of the last message of each batch the copy consumer reads",
      unit: :seconds,
      buckets: [1, 5, 15, 30, 60, 120, 300, 900]
  end

  # Draft tax requests answered from the cache instead of the tax provider. Tags are bounded by
  # the provider list.
  group :tax_providers do
    counter :draft_taxes_cache_total,
      comment: "Draft tax requests, by whether the cache answered them (hit) or the provider did (miss)",
      tags: %i[provider outcome]
    counter :draft_tax_rates_cache_total,
      comment: "Draft tax requests that accept cached rates, by what answered them: the rates (hit), the exact cache (exact), the provider after a missing rate (miss), or the provider because a line can't be priced from rates (skipped)",
      tags: %i[provider outcome]
  end

  # Cursor pagination of the v2 lists. Tags are bounded by the paginated tables and the error
  # codes; request latency per endpoint is already covered by yabeda-rails.
  group :api_pagination do
    counter :total_counts_total,
      comment: "Totals computed for include_total_count, by whether they are exact or why they are estimated",
      tags: %i[table outcome]

    counter :errors_total,
      comment: "Rejected pagination parameters, by error code",
      tags: %i[code]
  end

  # A split means a payment term changed between the hourly grouping and the job run, so the
  # rate should stay near zero.
  group :payment_terms do
    counter :splits_total,
      comment: "BillSubscriptionJob runs that found mixed payment terms and split into one job per term",
      tags: %i[invoicing_reason]
  end
end
