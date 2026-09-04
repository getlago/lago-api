# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::MergePeriodFeesService do
  subject(:merge_service) { described_class.new(earlier_fees:, later_fees:) }

  describe "#call" do
    context "when a charge filter has usage in both windows" do
      let(:charge_filter_id) { SecureRandom.uuid }

      let(:earlier_fee) do
        build(
          :charge_fee,
          charge_filter_id:,
          amount_cents: 100,
          precise_amount_cents: 100,
          units: 10,
          total_aggregated_units: 5,
          events_count: 3,
          invoice_display_name: "Earlier fee"
        )
      end

      let(:later_fee) do
        build(
          :charge_fee,
          charge_filter_id:,
          amount_cents: 200,
          precise_amount_cents: 200,
          units: 20,
          total_aggregated_units: 15,
          events_count: 7,
          invoice_display_name: "Later fee"
        )
      end

      let(:earlier_fees) { [earlier_fee] }
      let(:later_fees) { [later_fee] }

      it "sums every summed attribute and keeps the later fee's display attributes" do
        result = merge_service.call

        expect(result).to be_success
        merged = result.fees.first

        expect(result.fees.size).to eq(1)
        expect(merged).to equal(later_fee)
        expect(merged).to have_attributes(
          charge_filter_id:,
          amount_cents: 300,
          precise_amount_cents: 300,
          units: 30,
          total_aggregated_units: 20,
          events_count: 10,
          invoice_display_name: "Later fee"
        )
      end
    end

    context "when a charge filter only had usage in the earlier window" do
      let(:earlier_fee) { build(:charge_fee, charge_filter_id: SecureRandom.uuid, amount_cents: 50) }
      let(:earlier_fees) { [earlier_fee] }
      let(:later_fees) { [] }

      it "returns the earlier fee unchanged" do
        result = merge_service.call

        expect(result.fees.size).to eq(1)
        expect(result.fees.first).to equal(earlier_fee)
        expect(result.fees.first.amount_cents).to eq(50)
      end
    end

    context "when a charge filter only had usage in the later window" do
      let(:later_fee) { build(:charge_fee, charge_filter_id: SecureRandom.uuid, amount_cents: 75) }
      let(:earlier_fees) { [] }
      let(:later_fees) { [later_fee] }

      it "returns the later fee unchanged" do
        result = merge_service.call

        expect(result.fees.size).to eq(1)
        expect(result.fees.first).to equal(later_fee)
        expect(result.fees.first.amount_cents).to eq(75)
      end
    end

    context "when the default charge filter bucket sits alongside a real filter" do
      let(:real_filter_id) { SecureRandom.uuid }

      let(:earlier_default_fee) { build(:charge_fee, charge_filter_id: nil, amount_cents: 10) }
      let(:later_default_fee) { build(:charge_fee, charge_filter_id: nil, amount_cents: 20) }
      let(:earlier_filtered_fee) { build(:charge_fee, charge_filter_id: real_filter_id, amount_cents: 1) }
      let(:later_filtered_fee) { build(:charge_fee, charge_filter_id: real_filter_id, amount_cents: 2) }

      let(:earlier_fees) { [earlier_default_fee, earlier_filtered_fee] }
      let(:later_fees) { [later_default_fee, later_filtered_fee] }

      it "merges the nil bucket independently from the real filter" do
        result = merge_service.call

        expect(result.fees.size).to eq(2)

        default_fee = result.fees.find { |fee| fee.charge_filter_id.nil? }
        filtered_fee = result.fees.find { |fee| fee.charge_filter_id == real_filter_id }

        expect(default_fee.amount_cents).to eq(30)
        expect(filtered_fee.amount_cents).to eq(3)
      end
    end

    context "when total_aggregated_units is nil on one side" do
      let(:charge_filter_id) { SecureRandom.uuid }
      let(:earlier_fees) { [earlier_fee] }
      let(:later_fees) { [later_fee] }

      context "and the earlier fee has no total_aggregated_units" do
        let(:earlier_fee) { build(:charge_fee, charge_filter_id:, total_aggregated_units: nil) }
        let(:later_fee) { build(:charge_fee, charge_filter_id:, total_aggregated_units: 12) }

        it "treats the nil side as zero instead of raising" do
          result = nil

          expect { result = merge_service.call }.not_to raise_error
          expect(result.fees.first.total_aggregated_units).to eq(12)
        end
      end

      context "and the later fee has no total_aggregated_units" do
        let(:earlier_fee) { build(:charge_fee, charge_filter_id:, total_aggregated_units: 8) }
        let(:later_fee) { build(:charge_fee, charge_filter_id:, total_aggregated_units: nil) }

        it "treats the nil side as zero instead of raising" do
          result = nil

          expect { result = merge_service.call }.not_to raise_error
          expect(result.fees.first.total_aggregated_units).to eq(8)
        end
      end
    end

    context "with presentation breakdowns" do
      let(:charge_filter_id) { SecureRandom.uuid }
      let(:earlier_fee) { build(:charge_fee, charge_filter_id:) }
      let(:later_fee) { build(:charge_fee, charge_filter_id:) }
      let(:earlier_fees) { [earlier_fee] }
      let(:later_fees) { [later_fee] }

      before do
        earlier_fee.presentation_breakdowns.build(
          organization: earlier_fee.organization,
          presentation_by: {"department" => "engineering"},
          units: 10
        )
        earlier_fee.presentation_breakdowns.build(
          organization: earlier_fee.organization,
          presentation_by: {"department" => "support"},
          units: 4
        )
        later_fee.presentation_breakdowns.build(
          organization: later_fee.organization,
          presentation_by: {"department" => "engineering"},
          units: 6
        )
        later_fee.presentation_breakdowns.build(
          organization: later_fee.organization,
          presentation_by: {"department" => "sales"},
          units: 3
        )
      end

      it "sums units for matching presentation_by and appends the non-matching ones" do
        result = merge_service.call

        breakdowns = result.fees.first.presentation_breakdowns

        expect(breakdowns).to match_array([
          have_attributes(presentation_by: {"department" => "engineering"}, units: 16),
          have_attributes(presentation_by: {"department" => "sales"}, units: 3),
          have_attributes(presentation_by: {"department" => "support"}, units: 4)
        ])
      end
    end

    context "with pricing_unit_usage" do
      let(:charge_filter_id) { SecureRandom.uuid }
      let(:pricing_unit) { create(:pricing_unit) }
      let(:earlier_fee) { build(:charge_fee, charge_filter_id:) }
      let(:later_fee) { build(:charge_fee, charge_filter_id:) }
      let(:earlier_fees) { [earlier_fee] }
      let(:later_fees) { [later_fee] }

      context "when both fees have a pricing_unit_usage" do
        before do
          earlier_fee.pricing_unit_usage = build(
            :pricing_unit_usage,
            fee: nil,
            organization: earlier_fee.organization,
            pricing_unit:,
            amount_cents: 100,
            precise_amount_cents: 100
          )
          later_fee.pricing_unit_usage = build(
            :pricing_unit_usage,
            fee: nil,
            organization: later_fee.organization,
            pricing_unit:,
            amount_cents: 50,
            precise_amount_cents: 50
          )
        end

        it "sums the pricing_unit_usage amounts" do
          result = merge_service.call

          expect(result.fees.first.pricing_unit_usage).to have_attributes(
            amount_cents: 150,
            precise_amount_cents: 150
          )
        end
      end

      context "when only the later fee has a pricing_unit_usage" do
        before do
          later_fee.pricing_unit_usage = build(
            :pricing_unit_usage,
            fee: nil,
            organization: later_fee.organization,
            pricing_unit:,
            amount_cents: 50,
            precise_amount_cents: 50
          )
        end

        it "leaves the existing pricing_unit_usage untouched" do
          result = merge_service.call

          expect(result.fees.first.pricing_unit_usage).to have_attributes(
            amount_cents: 50,
            precise_amount_cents: 50
          )
        end
      end

      context "when only the earlier fee has a pricing_unit_usage" do
        before do
          earlier_fee.pricing_unit_usage = build(
            :pricing_unit_usage,
            fee: nil,
            organization: earlier_fee.organization,
            pricing_unit:,
            amount_cents: 100,
            precise_amount_cents: 100
          )
        end

        it "carries it onto the merged (later) fee" do
          result = merge_service.call

          expect(result.fees.first.pricing_unit_usage).to have_attributes(
            amount_cents: 100,
            precise_amount_cents: 100
          )
        end
      end
    end

    context "ordering" do
      let(:shared_filter_id) { SecureRandom.uuid }
      let(:later_only_filter_id) { SecureRandom.uuid }
      let(:earlier_only_filter_id) { SecureRandom.uuid }

      let(:earlier_fees) do
        [
          build(:charge_fee, charge_filter_id: earlier_only_filter_id),
          build(:charge_fee, charge_filter_id: shared_filter_id)
        ]
      end

      let(:later_fees) do
        [
          build(:charge_fee, charge_filter_id: shared_filter_id),
          build(:charge_fee, charge_filter_id: later_only_filter_id)
        ]
      end

      it "returns later-window filters first, followed by earlier-only filters" do
        result = merge_service.call

        expect(result.fees.map(&:charge_filter_id)).to eq(
          [shared_filter_id, later_only_filter_id, earlier_only_filter_id]
        )
      end
    end
  end
end
