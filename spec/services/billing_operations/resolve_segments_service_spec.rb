# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ResolveSegmentsService do
  describe ".call!" do
    subject(:segments) { described_class.call!(operation:).segments }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1)) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) do
      create(:rate_card, :advance, organization:, product:, currency: "USD")
    end
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1), units: 1)
    end
    let(:timestamp) { Time.utc(2026, 3, 1) }
    let(:operation) { BillingOperations::CreateInitialOperationService.call!(contract_rate_card:, causation_type: "contract_activation").billing_operations.sole }

    before { organization.enable_feature_flag!(:product_catalog) }

    it "rebuilds a priced PORO without writing a segment row" do
      create(:rate_card_rate, organization:, rate_card:, rate_model: "standard", rate_properties: {"amount" => "10"})
      operation

      expect { expect(segments).to all(be_a(BillingSegment)) }
        .not_to change(LegacyBillingSegment, :count)
      expect(segments).not_to respond_to(:save!)
    end

    context "when replaying current pricing" do
      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
          rate_model: "standard", rate_properties: {"amount" => "10"})
        operation
      end

      context "with a newly priced neighboring operation slice" do
        let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD", proration: true) }
        let(:later_rate) do
          create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15),
            rate_model: "standard", rate_properties: {"amount" => "20"})
        end

        before { later_rate }

        it "returns the matching advance slice and its same-cycle successor" do
          result = described_class.call!(operation:)

          expect(result.planned_operation).to have_attributes(billing_at: Time.utc(2026, 1, 1))
          expect(result.next_planned_operation).to have_attributes(billing_at: Time.utc(2026, 1, 15))
          expect(result.segments.map { [it.started_at, it.ended_at, it.proration_ratio] }).to eq(
            [[Time.utc(2026, 1, 1), BillingSegment.inclusive_end(Time.utc(2026, 1, 15)), BigDecimal(14).div(31, 10)]]
            # 14 days of the 31-day January billing cycle.
          )
        end

        it "does not replay the newly priced slice" do
          expect(segments.map(&:rate_card_rate_id)).to eq([rate_card.rates.order(:effective_from).first.id])
          expect(segments.map(&:started_at)).to eq([Time.utc(2026, 1, 1)])
          expect(segments.sole.ended_at).to eq(BillingSegment.inclusive_end(Time.utc(2026, 1, 15)))
          expect(later_rate).to be_persisted
        end
      end

      context "when an arrears cycle is split by a price change" do
        let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
        let(:operation) do
          create(:billing_operation, organization:, customer:, contract_rate_card:,
            action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 1, 15),
            target_cycle_started_at: Time.utc(2026, 1, 1))
        end

        before do
          create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15),
            rate_model: "standard", rate_properties: {"amount" => "20"},
            billing_interval_count: 1, billing_interval_unit: "month")
        end

        it "matches the arrears date and returns the next same-cycle operation" do
          result = described_class.call!(operation:)

          expect(result.planned_operation).to have_attributes(billing_at: Time.utc(2026, 1, 15))
          expect(result.next_planned_operation).to have_attributes(billing_at: Time.utc(2026, 2, 1))
          expect(result.segments.map { [it.started_at, it.billing_at] }).to eq(
            [[Time.utc(2026, 1, 1), operation.billing_at]]
          )
        end
      end

      context "when the current schedule no longer covers the stored cycle" do
        let(:short_cycle) do
          Data.define(:started_at, :ended_at).new(
            operation.target_cycle_started_at, operation.target_cycle_started_at + 1.week
          )
        end
        let(:schedule) do
          instance_double(BillingOperations::Schedule, cycle_at: short_cycle, planned_operations_for_cycle: [])
        end

        before do
          allow(BillingOperations::BuildScheduleService).to receive(:call!).and_return(double(schedule:))
        end

        it "leaves the operation pending without output or a successor" do
          result = described_class.call(operation:)

          expect(result).to be_success
          expect(result.segments).to be_empty
          expect(operation.reload).to have_attributes(processed_at: nil, cancelled_at: nil)
          expect(contract_rate_card.billing_operations.count).to eq(1)
        end
      end

      context "when the original cycle was clipped by contract termination" do
        let(:contract) do
          create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 15))
        end
        let(:operation) do
          create(:billing_operation, organization:, customer:, contract_rate_card:,
            action_type: "renew_fixed_advance", billing_at: Time.utc(2026, 1, 1),
            target_cycle_started_at: Time.utc(2026, 1, 1))
        end

        it "resolves clipped coverage from the saved billing instant without changing operation identity" do
          expect(segments.sole).to have_attributes(
            started_at: Time.utc(2026, 1, 1), ended_at: BillingSegment.inclusive_end(Time.utc(2026, 1, 15))
          )
          expect(operation.reload).to have_attributes(
            action_type: "renew_fixed_advance",
            billing_at: Time.utc(2026, 1, 1),
            target_cycle_started_at: Time.utc(2026, 1, 1),
            processed_at: nil,
            cancelled_at: nil
          )
        end
      end
    end

    context "when the target cycle is at or after contract end" do
      let(:contract) do
        create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 15))
      end
      let(:target_cycle_started_at) { Time.utc(2026, 1, 15) }
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "renew_fixed_advance", billing_at: target_cycle_started_at,
          target_cycle_started_at:)
      end

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
          billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "returns no match at the contract end" do
        result = described_class.call!(operation:)

        expect(result).to have_attributes(segments: be_empty, planned_operation: be_nil, next_planned_operation: be_nil)
      end

      context "when the target cycle starts after contract end" do
        let(:target_cycle_started_at) { Time.utc(2026, 2, 1) }

        it "returns no match after the contract end" do
          result = described_class.call!(operation:)

          expect(result).to have_attributes(segments: be_empty, planned_operation: be_nil,
            next_planned_operation: be_nil)
        end
      end
    end

    context "when the stored billing date is no longer scheduled" do
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "renew_fixed_advance", billing_at: Time.utc(2026, 1, 2),
          target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
          billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "returns no segments instead of selecting a neighboring operation" do
        result = described_class.call!(operation:)

        expect(result).to have_attributes(segments: be_empty, planned_operation: be_nil, next_planned_operation: be_nil)
      end
    end

    context "when resolving a termination operation" do
      let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "close_fixed_arrears", causation_type: "contract_termination",
          billing_at: Time.utc(2026, 1, 15), target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
          billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "selects the last planned group without a successor and adapts segments to the stored date" do
        result = described_class.call!(operation:)

        expect(result.planned_operation).to have_attributes(billing_at: Time.utc(2026, 2, 1))
        expect(result.next_planned_operation).to be_nil
        expect(result.segments.map(&:billing_at)).to eq([operation.billing_at])
      end
    end

    context "when the operation has no schedule action" do
      let(:operation) do
        build(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: nil, billing_at: Time.utc(2026, 1, 1), target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
          billing_interval_count: 1, billing_interval_unit: "month")
        allow(BillingOperations::BuildScheduleService).to receive(:call!).and_call_original
      end

      it "builds the schedule and returns an empty successful resolution" do
        result = described_class.call!(operation:)

        expect(result).to have_attributes(segments: be_empty, schedule: be_present,
          planned_operation: be_nil, next_planned_operation: be_nil)
        expect(BillingOperations::BuildScheduleService).to have_received(:call!).once
      end
    end

    context "when the stored cycle is absent from the schedule" do
      let(:operation) do
        build(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "renew_fixed_advance", billing_at: Time.utc(2026, 1, 1),
          target_cycle_started_at: Time.utc(2026, 1, 1))
      end
      let(:schedule) { instance_double(BillingOperations::Schedule, cycle_at: nil) }

      before do
        allow(BillingOperations::BuildScheduleService).to receive(:call!).and_return(double(schedule:))
      end

      it "returns a successful empty resolution" do
        result = described_class.call!(operation:)

        expect(result).to have_attributes(segments: be_empty, schedule:, planned_operation: be_nil,
          next_planned_operation: be_nil)
      end
    end

    context "when the operation is an unsupported reconciliation" do
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "reconcile_advance_coverage", billing_at: Time.utc(2026, 1, 1),
          target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      it "returns the validation failure" do
        expect(described_class.call(operation:)).to be_failure
      end
    end

    context "when schedule construction fails" do
      let(:operation) do
        build(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "renew_fixed_advance", billing_at: Time.utc(2026, 1, 1),
          target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      it "propagates the failure" do
        result = described_class.call(operation:)

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("rate")
      end
    end
  end
end
