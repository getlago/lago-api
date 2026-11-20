# frozen_string_literal: true

FactoryBot.define do
  factory :clickhouse_product_usage_bucket, class: "Clickhouse::ProductUsageBucket" do
    transient do
      contract { create(:contract) }
      organization { contract.organization }
      product { create(:product, :metered, organization:) }
      product_filters { [] }
    end

    organization_id { organization.id }
    contract_id { contract.id }
    customer_id { contract.customer_id }
    code { product.billable_metric.code }
    product_id { product.id }
    matched_filter_ids { product_filters.map(&:id).sort.join(",") }
    grouped_by { "{}" }
    aggregation_type { "count" }
    bucket { Time.current.beginning_of_hour }
    events_count { 1 }
    units { "1.0" }
    precise_total_amount_cents { "0.0" }
    last_event_at { Time.current.beginning_of_hour }
    last_ingested_at { Time.current }
    is_deleted { 0 }

    # RisingWave owns every write, so the model is read-only (see the usage bucket factory).
    to_create do |usage_bucket|
      Clickhouse::ProductUsageBucket.insert_all([usage_bucket.attributes.except("ver")]) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
