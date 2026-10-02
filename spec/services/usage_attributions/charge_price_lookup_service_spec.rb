# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributions::ChargePriceLookupService do
  subject(:lookup) { described_class.call!(charge:, currency:).lookup }

  let(:organization) { create(:organization) }
  let(:currency) { Money::Currency.new("EUR") }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) { create(:standard_charge, organization:, billable_metric:, properties: {"amount" => "1"}) }
  let(:model_filter) { create(:billable_metric_filter, billable_metric:, key: "model", values: %w[opus sonnet haiku]) }
  let(:region_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }

  let(:opus_filter) { create(:charge_filter, charge:, properties: {"amount" => "10"}, updated_at: 4.days.ago) }
  let(:opus_eu_filter) { create(:charge_filter, charge:, properties: {"amount" => "20"}, updated_at: 3.days.ago) }
  let(:small_models_filter) { create(:charge_filter, charge:, properties: {"amount" => "3"}, updated_at: 2.days.ago) }
  let(:all_regions_filter) { create(:charge_filter, charge:, properties: {"amount" => "0.5"}, updated_at: 1.day.ago) }

  let(:opus_value) { create(:charge_filter_value, charge_filter: opus_filter, billable_metric_filter: model_filter, values: ["opus"]) }

  before do
    opus_value
    create(:charge_filter_value, charge_filter: opus_eu_filter, billable_metric_filter: model_filter, values: ["opus"])
    create(:charge_filter_value, charge_filter: opus_eu_filter, billable_metric_filter: region_filter, values: ["eu"])
    create(:charge_filter_value, charge_filter: small_models_filter, billable_metric_filter: model_filter, values: %w[sonnet haiku])
    create(:charge_filter_value, charge_filter: all_regions_filter, billable_metric_filter: region_filter, values: [ChargeFilterValue::ALL_FILTER_VALUES])
  end

  it "ranks the filters by specificity, then by age" do
    expect(lookup.filter_ids).to eq([opus_eu_filter.id, opus_filter.id, small_models_filter.id, all_regions_filter.id])
  end

  it "maps the values of each key set to the rank of their best filter" do
    expect(lookup.key_sets).to eq(
      [
        [%w[model region], {"opus\u001Feu" => 1}],
        [%w[model], {"opus" => 2, "sonnet" => 3, "haiku" => 3}],
        [%w[region], {"eu" => 4, "us" => 4}]
      ]
    )
  end

  it "returns the unit amount of each filter in cents" do
    expect(lookup.unit_amounts_cents).to eq([2_000, 1_000, 300, 50])
  end

  context "with a charge priced in a pricing unit" do
    before { create(:applied_pricing_unit, organization:, pricing_unitable: charge, conversion_rate: 2) }

    it "converts the unit amounts" do
      expect(lookup.unit_amounts_cents).to eq([4_000, 2_000, 600, 100])
    end
  end

  context "with a discarded filter" do
    let(:small_models_filter) { create(:charge_filter, charge:, properties: {"amount" => "3"}, updated_at: 2.days.ago, deleted_at: Time.current) }

    it "leaves it out" do
      expect(lookup.filter_ids).to eq([opus_eu_filter.id, opus_filter.id, all_regions_filter.id])
    end
  end

  context "when the expanded values exceed the limit" do
    before { stub_const("#{described_class}::MAX_ENTRIES", 5) }

    it "returns no lookup" do
      expect(lookup).to be_nil
    end
  end

  context "with a cache store" do
    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "reuses the lookup until a filter value changes" do
      described_class.call!(charge:, currency:)
      opus_value.update_columns(values: ["haiku"]) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.call!(charge:, currency:).lookup.key_sets.second.last).to include("opus" => 2)

      opus_value.touch # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.call!(charge:, currency:).lookup.key_sets.second.last).to eq("haiku" => 2, "sonnet" => 3)
    end
  end
end
