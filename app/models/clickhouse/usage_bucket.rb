# frozen_string_literal: true

module Clickhouse
  class UsageBucket < BaseRecord
    self.table_name = "usage_buckets_15m"
    self.primary_key = [:organization_id, :subscription_id, :charge_id, :charge_filter_id, :grouped_by, :bucket]

    default_scope { final }

    def readonly?
      true
    end
  end
end

# == Schema Information
#
# Table name: usage_buckets_15m
# Database name: clickhouse
#
#  aggregation_type   :string           not null
#  bucket             :datetime         not null, primary key
#  code               :string           not null
#  events_count       :integer          not null
#  grouped_by         :string           not null, primary key
#  is_deleted         :integer          default(0), not null
#  last_event_at      :datetime         not null
#  last_ingested_at   :datetime         not null
#  target_wallet_code :string
#  units              :decimal(38, 20)  not null
#  charge_filter_id   :string           not null, primary key
#  charge_id          :string           not null, primary key
#  customer_id        :string           not null
#  organization_id    :string           not null, primary key
#  plan_id            :string
#  subscription_id    :string           not null, primary key
#
