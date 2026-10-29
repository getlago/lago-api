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

    let(:organization) { create(:organization) }
    let(:billable_metric) { build_stubbed(:sum_billable_metric, :recurring) }
    let(:metered_item) { instance_double(Fees::ChargeService::MeteredItem, billable_metric:, billing_segment: nil) }
    let(:billing_context) { Billing::Context.from(subscription: build_stubbed(:subscription, organization:)) }

    before { organization.enable_feature_flag!(:persisted_recurring_values) }

    it { is_expected.to be(true) }

    context "without the persisted_recurring_values feature flag" do
      before { organization.disable_feature_flag!(:persisted_recurring_values) }

      it { is_expected.to be(false) }
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
