# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::Reports::DimensionKey do
  subject(:dimension_key) { described_class.build(organization:, charge_filter_ids: [charge_filter.id]) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, billable_metric:, organization:) }
  let(:charge_filter) { create(:charge_filter, charge:, organization:) }
  let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
  let(:tier) { create(:billable_metric_filter, billable_metric:, key: "tier", values: %w[gold silver]) }

  before do
    create(:charge_filter_value, charge_filter:, billable_metric_filter: region, values: %w[us eu])
    create(:charge_filter_value, charge_filter:, billable_metric_filter: tier, values: [ChargeFilterValue::ALL_FILTER_VALUES])
  end

  it "keys a filter on its sorted values, whatever its id" do
    other_filter = create(:charge_filter, charge: create(:standard_charge, billable_metric:, organization:), organization:)
    create(:charge_filter_value, charge_filter: other_filter, billable_metric_filter: tier, values: [ChargeFilterValue::ALL_FILTER_VALUES])
    create(:charge_filter_value, charge_filter: other_filter, billable_metric_filter: region, values: %w[eu us])

    other_key = described_class.build(organization:, charge_filter_ids: [other_filter.id])

    expect(other_key.sql).to include(%({"region":["eu","us"],"tier":["__ALL_FILTER_VALUES__"]}))
    expect(dimension_key.sql).to include(%({"region":["eu","us"],"tier":["__ALL_FILTER_VALUES__"]}))
  end

  it "names a dimension after its values, and a filter on every value after its key" do
    key = %({"region":["eu","us"],"tier":["__ALL_FILTER_VALUES__"]}#{described_class::SEPARATOR}{"model":"sonnet"})

    expect(dimension_key.dimension(key).to_h).to eq(
      key:,
      name: "eu, us, tier, sonnet",
      values: {"region" => %w[eu us], "tier" => [ChargeFilterValue::ALL_FILTER_VALUES], "model" => ["sonnet"]}
    )
  end

  it "gives the charge default no name" do
    expect(dimension_key.dimension(described_class::SEPARATOR).to_h).to eq(key: described_class::SEPARATOR, name: nil, values: {})
  end

  context "with a deleted filter" do
    before { charge_filter.values.each(&:discard!) && charge_filter.discard! }

    it "keeps the values it had" do
      expect(dimension_key.sql).to include(%({"region":["eu","us"],"tier":["__ALL_FILTER_VALUES__"]}))
    end
  end

  context "with a deleted filter whose value on a key was replaced while it was used" do
    before do
      charge_filter.values.find_by(billable_metric_filter: region).update!(deleted_at: 2.days.ago, updated_at: 2.days.ago)
      create(:charge_filter_value, charge_filter:, billable_metric_filter: region, values: %w[eu])
      charge_filter.values.each(&:discard!) && charge_filter.discard!
    end

    it "keys it on the values it had when it was deleted, as billing names it" do
      expect(dimension_key.sql).to include(%({"region":["eu"],"tier":["__ALL_FILTER_VALUES__"]}))
      expect(dimension_key.sql).not_to include("us")
    end
  end

  context "with a value removed from a filter that is still used" do
    before { charge_filter.values.find_by(billable_metric_filter: tier).discard! }

    it "only keys the current values" do
      expect(dimension_key.sql).to include(%({"region":["eu","us"]}))
      expect(dimension_key.sql).not_to include("tier")
    end
  end

  context "with another organization's filter" do
    subject(:dimension_key) { described_class.build(organization: create(:organization), charge_filter_ids: [charge_filter.id]) }

    it "ignores it" do
      expect(dimension_key.sql).to start_with("concat('', char(31)")
    end
  end
end
