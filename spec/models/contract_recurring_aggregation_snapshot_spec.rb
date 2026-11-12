# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRecurringAggregationSnapshot do
  subject(:snapshot) { build(:contract_recurring_aggregation_snapshot) }

  describe "associations" do
    it do
      expect(snapshot).to belong_to(:organization)
      expect(snapshot).to belong_to(:contract)
      expect(snapshot).to belong_to(:product)
      expect(snapshot).to belong_to(:product_filter).optional
      expect(snapshot).to belong_to(:billable_metric)
    end
  end

  describe "Scopes" do
    let(:product) { create(:product) }
    let(:product_filter) { create(:product_filter, organization: product.organization, product:) }
    let(:marker) do
      create(:contract_recurring_aggregation_snapshot, organization: product.organization, product:, product_filter:,
        to_datetime: Time.zone.parse("2026-09-30T23:59:59"))
    end

    def create_snapshot(**attributes)
      create(:contract_recurring_aggregation_snapshot, organization: marker.organization, contract: marker.contract,
        product: marker.product, product_filter: marker.product_filter, **attributes)
    end

    describe ".latest_period" do
      let(:older_snapshot) { create_snapshot(to_datetime: Time.zone.parse("2026-08-31T23:59:59")) }
      let(:group_snapshot) { create_snapshot(to_datetime: marker.to_datetime, grouped_by: {"region" => "eu"}) }

      before do
        older_snapshot
        group_snapshot
      end

      it "returns every snapshot of the bucket's latest period, as each one marks it" do
        expect(described_class.latest_period([product_filter.id])).to match_array([marker, group_snapshot])
      end

      it "returns the latest period closed before the given time" do
        expect(described_class.latest_period([product_filter.id], before: marker.to_datetime)).to eq([older_snapshot])
      end
    end

    describe ".of_group" do
      let(:marker) do
        create(:contract_recurring_aggregation_snapshot, organization: product.organization, product:, product_filter:,
          grouped_by: {"region" => nil})
      end
      let(:eu_snapshot) { create_snapshot(to_datetime: marker.to_datetime, grouped_by: {"region" => "eu"}) }

      before do
        eu_snapshot
        create_snapshot(to_datetime: marker.to_datetime, grouped_by: {"region" => "us"})
      end

      it "returns the group's snapshots and the first snapshot of the bucket" do
        expect(described_class.of_group({"region" => "eu"}, grouped_by_keys: %w[region], bucket_ids: [product_filter.id]))
          .to match_array([marker, eu_snapshot])
      end
    end
  end

  describe "validations" do
    it do
      expect(snapshot).to validate_presence_of(:to_datetime)
      expect(snapshot).to validate_presence_of(:watermark)
      expect(snapshot).to validate_numericality_of(:units)
    end
  end

  describe ".filters_changed_since?" do
    subject(:filters_changed) do
      described_class.filters_changed_since?(organization_id: organization.id, contract_id: contract.id, product_id: product.id, watermark:)
    end

    let(:watermark) { Time.zone.parse("2026-10-01T00:05:00") }
    let(:before_watermark) { watermark - 1.month }
    let(:after_watermark) { watermark + 1.minute }
    let(:organization) { create(:organization) }
    let(:contract) { create(:contract, organization:, customer: create(:customer, organization:)) }
    let(:product) { create(:product, organization:) }
    let(:billable_metric_filter) do
      create(:billable_metric_filter, billable_metric: product.billable_metric, values: %w[eu us], updated_at: before_watermark)
    end
    let(:product_filter) { create(:product_filter, organization:, product:, created_at: before_watermark) }
    let(:value) { "eu" }
    let(:product_filter_value) do
      create(:product_filter_value, organization:, product_filter:, billable_metric_filter:, value:,
        created_at: before_watermark, updated_at: before_watermark)
    end
    let(:rate_card) { create(:rate_card, organization:, product:, product_filter:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:, created_at: before_watermark) }

    before do
      product_filter_value
      contract_rate_card
    end

    it { is_expected.to be(false) }

    context "when a filter of the product was created after the watermark" do
      before { create(:product_filter, organization:, product:, created_at: after_watermark) }

      it { is_expected.to be(true) }
    end

    context "when a filter of the product was removed after the watermark" do
      before { product_filter.update_columns(deleted_at: after_watermark) } # rubocop:disable Rails/SkipsModelValidations

      it { is_expected.to be(true) }
    end

    context "when a filter value was edited after the watermark" do
      before { product_filter_value.update_columns(updated_at: after_watermark) } # rubocop:disable Rails/SkipsModelValidations

      it { is_expected.to be(true) }
    end

    context "when a filter value was removed after the watermark" do
      before { product_filter_value.update_columns(deleted_at: after_watermark) } # rubocop:disable Rails/SkipsModelValidations

      it { is_expected.to be(true) }
    end

    context "when a filter of another product changed after the watermark" do
      before { create(:product_filter, organization:, created_at: after_watermark) }

      it { is_expected.to be(false) }
    end

    context "when the metric filter of a value listing its value changed after the watermark" do
      before { billable_metric_filter.update_columns(updated_at: after_watermark) } # rubocop:disable Rails/SkipsModelValidations

      it { is_expected.to be(false) }
    end

    context "with a value set to all values of the metric filter" do
      let(:value) { nil }

      it { is_expected.to be(false) }

      context "when the metric filter changed after the watermark" do
        before { billable_metric_filter.update_columns(updated_at: after_watermark) } # rubocop:disable Rails/SkipsModelValidations

        it { is_expected.to be(true) }
      end

      context "when the metric filter was removed after the watermark" do
        before { billable_metric_filter.update_columns(deleted_at: after_watermark) } # rubocop:disable Rails/SkipsModelValidations

        it { is_expected.to be(true) }
      end
    end

    context "when the contract priced the product with another card after the watermark" do
      before do
        create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, product:), created_at: after_watermark)
      end

      it { is_expected.to be(true) }
    end

    context "when a card of the product was removed from the contract after the watermark" do
      before { contract_rate_card.update_columns(deleted_at: after_watermark) } # rubocop:disable Rails/SkipsModelValidations

      it { is_expected.to be(true) }
    end

    context "when the contract priced another product after the watermark" do
      before { create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:), created_at: after_watermark) }

      it { is_expected.to be(false) }
    end

    context "when another contract priced the product after the watermark" do
      before do
        other_contract = create(:contract, organization:, customer: create(:customer, organization:))
        create(:contract_rate_card, organization:, contract: other_contract, rate_card:, created_at: after_watermark)
      end

      it { is_expected.to be(false) }
    end
  end

  describe "unique index" do
    let(:product) { create(:product) }
    let(:existing) { create(:contract_recurring_aggregation_snapshot, organization: product.organization, product:, product_filter:, grouped_by:) }
    let(:product_filter) { nil }
    let(:grouped_by) { {} }
    let(:duplicate_to_datetime) { existing.to_datetime }
    let(:duplicate_product_filter) { existing.product_filter }
    let(:duplicate) do
      build(
        :contract_recurring_aggregation_snapshot,
        organization: existing.organization,
        contract: existing.contract,
        product: existing.product,
        product_filter: duplicate_product_filter,
        grouped_by: existing.grouped_by,
        to_datetime: duplicate_to_datetime
      )
    end

    context "without product filter" do
      it "rejects a second snapshot for the same period, treating NULL filters as equal" do
        expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "with grouped_by" do
      let(:grouped_by) { {"region" => "eu"} }

      it "rejects a second snapshot for the same group" do
        expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "with a product filter" do
      let(:product_filter) { create(:product_filter, organization: product.organization, product:) }

      it "rejects a second snapshot for the same filter" do
        expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "with a different product filter" do
      let(:product_filter) { create(:product_filter, organization: product.organization, product:) }
      let(:duplicate_product_filter) { nil }

      it "accepts the snapshot" do
        expect { duplicate.save! }.not_to raise_error
      end
    end

    context "with a different period" do
      let(:duplicate_to_datetime) { existing.to_datetime + 1.month }

      it "accepts the snapshot" do
        expect { duplicate.save! }.not_to raise_error
      end
    end
  end
end
