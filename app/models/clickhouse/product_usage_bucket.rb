# frozen_string_literal: true

module Clickhouse
  class ProductUsageBucket < BaseRecord
    self.table_name = "product_usage_buckets_15m"
    self.primary_key = [:organization_id, :contract_id, :product_id, :product_filter_id, :grouped_by, :bucket]

    default_scope { final }

    def readonly?
      true
    end
  end
end

# == Schema Information
#
# Table name: product_usage_buckets_15m
# Database name: clickhouse
#
#  aggregation_type           :string           not null
#  bucket                     :datetime         not null, primary key
#  code                       :string           not null
#  events_count               :integer          not null
#  grouped_by                 :string           not null, primary key
#  is_deleted                 :integer          default(0), not null
#  last_event_at              :datetime         not null
#  last_ingested_at           :datetime         not null
#  precise_total_amount_cents :decimal(38, 15)  default(0.0), not null
#  units                      :decimal(38, 20)  not null
#  ver                        :datetime         not null
#  contract_id                :string           not null, primary key
#  customer_id                :string           not null
#  organization_id            :string           not null, primary key
#  product_filter_id          :string           not null, primary key
#  product_id                 :string           not null, primary key
#
