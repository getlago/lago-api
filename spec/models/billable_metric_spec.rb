# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetric do
  subject(:billable_metric) { create(:billable_metric) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)

      expect(subject).to have_many(:alerts).class_name("UsageMonitoring::Alert")
      expect(subject).to have_many(:charges).dependent(:destroy)
      expect(subject).to have_many(:plans).through(:charges)
      expect(subject).to have_many(:fees).through(:charges)
      expect(subject).to have_many(:subscriptions).through(:plans)
      expect(subject).to have_many(:invoices).through(:fees)
      expect(subject).to have_many(:filters).dependent(:delete_all)
      expect(subject).to have_many(:netsuite_mappings).dependent(:destroy)
    end
  end

  describe "Clickhouse associations", clickhouse: true do
    it { is_expected.to have_many(:activity_logs).class_name("Clickhouse::ActivityLog") }
  end

  it { validate_presence_of(:field_name) }
  it { validate_presence_of(:custom_aggregator) }

  describe "#aggregation_type=" do
    let(:billable_metric) { described_class.new }

    it "assigns the aggregation type" do
      billable_metric.aggregation_type = :count_agg
      billable_metric.valid?

      aggregate_failures do
        expect(billable_metric).to be_count_agg
        expect(billable_metric.errors[:aggregation_type]).to be_blank
      end
    end

    context "when aggregation type is invalid" do
      it "does not assign the aggregation type" do
        billable_metric.aggregation_type = :invalid_agg
        billable_metric.valid?

        aggregate_failures do
          expect(billable_metric.aggregation_type).to be_nil
          expect(billable_metric.errors[:aggregation_type]).to include("value_is_invalid")
        end
      end
    end
  end

  describe "#validate_recurring" do
    let(:recurring) { false }
    let(:billable_metric) { build(:max_billable_metric, recurring:) }

    it "does not return an error if recurring is false for max_agg" do
      expect(billable_metric).to be_valid
    end

    context "when recurring is true" do
      let(:recurring) { true }

      it "returns an error for max_agg" do
        aggregate_failures do
          expect(billable_metric).not_to be_valid
          expect(billable_metric.errors.messages[:recurring]).to include("not_compatible_with_aggregation_type")
        end
      end
    end

    context "when recurring is true and aggregation type is latest_agg" do
      let(:billable_metric) { build(:latest_billable_metric, recurring:) }
      let(:recurring) { true }

      it "returns an error" do
        aggregate_failures do
          expect(billable_metric).not_to be_valid
          expect(billable_metric.errors.messages[:recurring]).to include("not_compatible_with_aggregation_type")
        end
      end
    end
  end

  describe "#validate_expression" do
    let(:expression) { "" }
    let(:billable_metric) { build(:max_billable_metric, expression:) }

    it "does not return an error if expression is blank" do
      expect(billable_metric).to be_valid
    end

    context "with valid expression" do
      let(:expression) { "1 + event.timestamp" }

      it "does not return an error" do
        expect(billable_metric).to be_valid
      end
    end

    context "when expression is not valid" do
      let(:expression) { "1+" }

      it "returns an error for expression" do
        aggregate_failures do
          expect(billable_metric).not_to be_valid
          expect(billable_metric.errors.messages[:expression]).to include("invalid_expression")
        end
      end
    end
  end

  describe "#payable_in_advance?" do
    it do
      described_class::AGGREGATION_TYPES_PAYABLE_IN_ADVANCE.each do |agg|
        expect(build(:billable_metric, aggregation_type: agg)).to be_payable_in_advance
      end

      (described_class::AGGREGATION_TYPES.keys - described_class::AGGREGATION_TYPES_PAYABLE_IN_ADVANCE).each do |agg|
        expect(build(:billable_metric, aggregation_type: agg)).not_to be_payable_in_advance
      end
    end
  end
end
