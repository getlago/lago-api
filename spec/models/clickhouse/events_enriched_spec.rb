# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clickhouse::EventsEnriched, clickhouse: true do
  subject(:events_enriched) { create(:clickhouse_events_enriched) }

  it "persists a record via the factory" do
    expect(events_enriched).to be_persisted
  end

  describe "attribution_labels" do
    it "defaults to an empty map" do
      expect(events_enriched.reload.attribution_labels).to eq({})
    end

    it "stores the resolved account tree labels" do
      record = create(
        :clickhouse_events_enriched,
        attribution_labels: {"user" => "alice", "department" => "rnd"}
      )

      expect(record.reload.attribution_labels).to eq({"user" => "alice", "department" => "rnd"})
    end

    it "rolls usage up through any level of the tree" do
      organization = create(:organization)
      subscription = create(:subscription, customer: create(:customer, organization:))
      billable_metric = create(:billable_metric, organization:)

      {alice: [1000, "rnd"], bob: [500, "rnd"], carol: [2000, "sales"]}.each do |user, (units, department)|
        create(
          :clickhouse_events_enriched,
          organization: organization,
          subscription: subscription,
          billable_metric: billable_metric,
          decimal_value: units,
          attribution_labels: {"user" => user.to_s, "department" => department}
        )
      end

      scope = described_class.where(organization_id: organization.id)

      per_user = scope.group("attribution_labels['user']").sum(:decimal_value)
      per_department = scope.group("attribution_labels['department']").sum(:decimal_value)

      expect(per_user).to eq({"alice" => 1000, "bob" => 500, "carol" => 2000})
      expect(per_department).to eq({"rnd" => 1500, "sales" => 2000})
      expect(per_department.values.sum).to eq(per_user.values.sum)
    end
  end

  describe ".table_name" do
    it "is events_enriched" do
      expect(described_class.table_name).to eq("events_enriched")
    end
  end

  describe ".primary_key" do
    it "matches the ClickHouse table primary key" do
      expect(described_class.primary_key).to eq(
        ["organization_id", "code", "external_subscription_id", "timestamp"]
      )
    end
  end
end
