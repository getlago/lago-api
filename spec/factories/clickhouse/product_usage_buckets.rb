# frozen_string_literal: true

FactoryBot.define do
  factory :clickhouse_product_usage_bucket, class: "Clickhouse::ProductUsageBucket" do
    transient do
      contract { create(:contract) }
      product { create(:product, organization: contract.organization) }
    end

    organization_id { contract.organization_id }
    contract_id { contract.id }
    customer_id { contract.customer_id }
    code { product.billable_metric&.code || "code" }
    product_id { product.id }
    product_filter_id { "" }
    grouped_by { "{}" }
    aggregation_type { "sum" }
    bucket { Time.current.beginning_of_hour }
    events_count { 1 }
    units { "21.0" }
    precise_total_amount_cents { "0.0" }
    last_event_at { Time.current.beginning_of_hour }
    last_ingested_at { Time.current }
    is_deleted { 0 }

    # The RisingWave sink owns every write to product_usage_buckets_15m, so the model is
    # read-only and `save` would raise. `ver` is MATERIALIZED and rejects an explicit value.
    to_create do |bucket|
      Clickhouse::ProductUsageBucket.insert_all([bucket.attributes.except("ver")]) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
