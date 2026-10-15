# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshot do
  subject(:snapshot) { build(:recurring_aggregation_snapshot) }

  describe "associations" do
    it do
      expect(snapshot).to belong_to(:organization)
      expect(snapshot).to belong_to(:subscription)
      expect(snapshot).to belong_to(:charge)
      expect(snapshot).to belong_to(:charge_filter).optional
      expect(snapshot).to belong_to(:billable_metric)
    end
  end

  describe "Scopes" do
    describe ".of_period" do
      let(:snapshot) { create(:recurring_aggregation_snapshot, to_datetime: Time.zone.parse("2026-09-30T23:59:59")) }

      before do
        create(:recurring_aggregation_snapshot, organization: snapshot.organization, subscription: snapshot.subscription,
          charge: snapshot.charge, to_datetime: Time.zone.parse("2026-08-31T23:59:59"))
      end

      it "returns the snapshots of the period the query selects" do
        latest_to_datetime = described_class.order(to_datetime: :desc).limit(1).select(:to_datetime)

        expect(described_class.of_period(latest_to_datetime)).to eq([snapshot])
      end
    end

    describe ".of_group" do
      let(:snapshot) { create(:recurring_aggregation_snapshot, grouped_by: {"region" => "eu", "cloud" => "aws"}) }
      let(:bucket_snapshots) do
        [{"region" => "eu", "cloud" => " "}, {"region" => "us", "cloud" => nil}, {"region" => "us", "cloud" => "aws"}].map do |grouped_by|
          create(:recurring_aggregation_snapshot, organization: snapshot.organization, subscription: snapshot.subscription,
            charge: snapshot.charge, grouped_by:)
        end
      end
      let(:first_snapshot) { ([snapshot] + bucket_snapshots).min_by(&:id) }

      it "returns the snapshots of the group and the first snapshot of the bucket" do
        expect(described_class.of_group({"region" => "us", "cloud" => "aws"})).to match_array([bucket_snapshots.last, first_snapshot].uniq)
      end

      it "matches a blank value with a missing one" do
        expect(described_class.of_group({"cloud" => ""})).to match_array([*bucket_snapshots.first(2), first_snapshot].uniq)
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

  describe ".eligible?" do
    subject(:eligible) { described_class.eligible?(metered_item:, billing_context:) }

    let(:billable_metric) { build_stubbed(:sum_billable_metric) }
    let(:billing_segment) { nil }
    let(:metered_item) { instance_double(Fees::ChargeService::MeteredItem, billable_metric:, billing_segment:) }
    let(:billing_context) { Billing::Context.from(subscription: build_stubbed(:subscription)) }

    it { is_expected.to be(true) }

    context "with a weighted sum metric" do
      let(:billable_metric) { build_stubbed(:weighted_sum_billable_metric) }

      it { is_expected.to be(true) }
    end

    context "with another aggregation type" do
      let(:billable_metric) { build_stubbed(:billable_metric, aggregation_type: "count_agg") }

      it { is_expected.to be(false) }
    end

    context "with a billing segment" do
      let(:billing_segment) { build_stubbed(:billing_segment) }

      it { is_expected.to be(false) }
    end

    context "with a contract billing context" do
      let(:billing_context) { Billing::Context.from(contract: build_stubbed(:contract)) }

      it { is_expected.to be(false) }
    end
  end

  describe ".readable?" do
    subject(:readable) { described_class.readable?(metered_item:, billing_context:) }

    let(:billable_metric) { build_stubbed(:sum_billable_metric, :recurring) }
    let(:metered_item) { instance_double(Fees::ChargeService::MeteredItem, billable_metric:, billing_segment: nil) }
    let(:billing_context) { Billing::Context.from(subscription: build_stubbed(:subscription)) }

    it { is_expected.to be(true) }

    context "when the snapshot read is forced off" do
      it "is false" do
        RecurringAggregationSnapshots.with_forced_read(false) { expect(readable).to be(false) }
      end
    end

    context "with a metric that is not recurring" do
      let(:billable_metric) { build_stubbed(:sum_billable_metric) }

      it { is_expected.to be(false) }
    end

    context "with an aggregation type without snapshots" do
      let(:billable_metric) { build_stubbed(:billable_metric, :recurring, aggregation_type: "count_agg") }

      it { is_expected.to be(false) }
    end
  end

  describe ".filters_changed_since?" do
    subject(:filters_changed) { described_class.filters_changed_since?(organization_id: charge.organization_id, charge_ids: charge.id, watermark:) }

    let(:watermark) { Time.zone.parse("2026-10-01T00:05:00") }
    let(:charge) { create(:standard_charge) }
    let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric: charge.billable_metric, values: %w[eu us]) }
    let(:charge_filter) { create(:charge_filter, charge:, created_at: watermark - 1.month) }
    let(:values) { %w[eu] }
    let(:charge_filter_value) do
      create(:charge_filter_value, charge_filter:, billable_metric_filter:, values:, created_at: watermark - 1.month, updated_at: watermark - 1.month)
    end

    before do
      charge_filter_value
      billable_metric_filter.update_columns(updated_at: watermark - 1.month) # rubocop:disable Rails/SkipsModelValidations
    end

    it { is_expected.to be(false) }

    context "when a filter was created after the watermark" do
      before { create(:charge_filter, charge:, created_at: watermark + 1.minute) }

      it { is_expected.to be(true) }
    end

    context "when a filter was removed after the watermark" do
      before { charge_filter.update_columns(deleted_at: watermark + 1.minute) } # rubocop:disable Rails/SkipsModelValidations

      it { is_expected.to be(true) }
    end

    context "when a filter value was edited after the watermark" do
      before { charge_filter_value.update_columns(updated_at: watermark + 1.minute) } # rubocop:disable Rails/SkipsModelValidations

      it { is_expected.to be(true) }
    end

    context "when a filter of another charge changed after the watermark" do
      before { create(:charge_filter, created_at: watermark + 1.minute) }

      it { is_expected.to be(false) }
    end

    context "when the metric filter of a value listing its values changed after the watermark" do
      before { billable_metric_filter.update_columns(updated_at: watermark + 1.minute) } # rubocop:disable Rails/SkipsModelValidations

      it { is_expected.to be(false) }
    end

    context "with a value set to all values of the metric filter" do
      let(:values) { [ChargeFilterValue::ALL_FILTER_VALUES] }

      it { is_expected.to be(false) }

      context "when the metric filter changed after the watermark" do
        before { billable_metric_filter.update_columns(updated_at: watermark + 1.minute) } # rubocop:disable Rails/SkipsModelValidations

        it { is_expected.to be(true) }
      end
    end
  end

  describe "unique index" do
    let(:existing) { create(:recurring_aggregation_snapshot, grouped_by:) }
    let(:grouped_by) { {} }
    let(:duplicate_to_datetime) { existing.to_datetime }
    let(:duplicate) do
      build(
        :recurring_aggregation_snapshot,
        organization: existing.organization,
        subscription: existing.subscription,
        charge: existing.charge,
        charge_filter: existing.charge_filter,
        grouped_by: existing.grouped_by,
        to_datetime: duplicate_to_datetime
      )
    end

    context "without charge filter" do
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

    context "with a different period" do
      let(:duplicate_to_datetime) { existing.to_datetime + 1.month }

      it "accepts the snapshot" do
        expect { duplicate.save! }.not_to raise_error
      end
    end
  end
end
