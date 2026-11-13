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
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "renew_fixed_advance", billing_at: Time.utc(2026, 1, 1),
        target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: Time.utc(2026, 1, 1))
    end

    before { organization.enable_feature_flag!(:product_catalog) }

    it "rebuilds a priced PORO without writing a segment row" do
      create(:rate_card_rate, organization:, rate_card:, rate_model: "standard", rate_properties: {"amount" => "10"})
      operation

      expect { expect(segments).to all(be_a(BillingSegment)) }
        .not_to change(LegacyBillingSegment, :count)
      expect(segments).not_to respond_to(:save!)
    end

    context "when the planner's next priced cycle follows the stored cycle" do
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "renew_fixed_advance", billing_at: Time.utc(2026, 1, 1),
          target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: Time.utc(2026, 1, 1))
      end

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 2, 15),
          billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "keeps the resolution on the operation's stored cycle" do
        resolution = described_class.call!(operation:)

        expect(resolution.schedule).to be_a(Billing::RateCards::Schedule)
        expect(resolution.cycle.started_at).to eq(Time.utc(2026, 1, 1))
        expect(resolution.segments).to be_empty
      end
    end

    context "when resolving regrouped paid fees" do
      let(:billable_metric) do
        create(:billable_metric, organization:, aggregation_type: :sum_agg, recurring: false, field_name: "units")
      end
      let(:product) { create(:product, organization:, billable_metric:) }
      let(:rate_card) do
        create(:rate_card, organization:, product:, billing_timing: "advance", regroup_paid_fees: :invoice,
          display_on_invoice: false, currency: "USD")
      end
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "regroup_paid_fees", billing_at: Time.utc(2026, 1, 15),
          target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
          billing_interval_count: 1, billing_interval_unit: "month")
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15),
          billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "uses segment end as the regroup date" do
        resolution = described_class.call!(operation:)

        expect(resolution.segments.map(&:started_at)).to eq([Time.utc(2026, 1, 1)])
      end
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

        it "returns the advance slice due at the operation date" do
          result = described_class.call!(operation:)

          expect(result.cycle).to have_attributes(started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 2, 1))
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
            target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: Time.utc(2026, 1, 15))
        end

        before do
          create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15),
            rate_model: "standard", rate_properties: {"amount" => "20"},
            billing_interval_count: 1, billing_interval_unit: "month")
        end

        it "returns only the slice due at the price change" do
          expect(segments.map { [it.started_at, it.billing_at] }).to eq(
            [[Time.utc(2026, 1, 1), operation.billing_at]]
          )
        end

        context "when the cycle close follows an operation at the price change" do
          let(:close) do
            create(:billing_operation, organization:, customer:, contract_rate_card:,
              action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 2, 1),
              target_cycle_started_at: Time.utc(2026, 1, 1))
          end
          let(:built_schedules) { [] }

          before do
            operation
            allow(Billing::RateCards::BuildScheduleService).to receive(:call!).and_wrap_original do |original, **attributes|
              original.call(**attributes).tap { built_schedules << it.schedule }
            end
          end

          it "returns only the slices after the previous operation" do
            result = described_class.call!(operation: close)

            expect(result.segments.map(&:started_at)).to eq([Time.utc(2026, 1, 15)])
            expect(Billing::RateCards::BuildScheduleService).to have_received(:call!).with(
              contract_rate_card:
            )
            expect(result.schedule).to be(built_schedules.sole)
          end

          context "when the previous operation was cancelled" do
            before do
              operation.update!(processed_at: nil, cancelled_at: Time.utc(2026, 1, 10), cancelled_causation_type: :contract_termination)
            end

            it "returns every slice of the cycle" do
              expect(described_class.call!(operation: close).segments.map(&:started_at))
                .to eq([Time.utc(2026, 1, 1), Time.utc(2026, 1, 15)])
            end
          end

          context "when the previous operation belongs to another cycle" do
            before { operation.update!(target_cycle_started_at: Time.utc(2025, 12, 1)) }

            it "returns every slice of the cycle" do
              expect(described_class.call!(operation: close).segments.map(&:started_at))
                .to eq([Time.utc(2026, 1, 1), Time.utc(2026, 1, 15)])
            end
          end
        end

        context "when the price change arrives after the cycle close was created" do
          let(:operation) do
            create(:billing_operation, organization:, customer:, contract_rate_card:,
              action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 2, 1),
              target_cycle_started_at: Time.utc(2026, 1, 1))
          end

          it "returns both slices instead of dropping the earlier one" do
            expect(segments.map { [it.started_at, it.ended_at] }).to eq([
              [Time.utc(2026, 1, 1), BillingSegment.inclusive_end(Time.utc(2026, 1, 15))],
              [Time.utc(2026, 1, 15), BillingSegment.inclusive_end(Time.utc(2026, 2, 1))]
            ])
          end
        end
      end

      context "when the current schedule no longer covers the stored cycle" do
        let(:short_cycle) do
          Data.define(:started_at, :ended_at).new(
            operation.target_cycle_started_at, operation.target_cycle_started_at + 1.week
          )
        end
        let(:schedule) do
          instance_double(Billing::RateCards::Schedule, cycle_at: short_cycle, segments_due_in_cycle: [])
        end

        before do
          allow(Billing::RateCards::BuildScheduleService).to receive(:call!).and_return(double(schedule:))
        end

        it "does not rewrite completed history when replay produces no segments" do
          result = described_class.call(operation:)

          expect(result).to be_success
          expect(result.segments).to be_empty
          expect(operation.reload).to have_attributes(processed_at: Time.utc(2026, 1, 1), cancelled_at: nil)
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
          result = described_class.call!(operation:)

          expect(result.segments.sole).to have_attributes(
            started_at: Time.utc(2026, 1, 1), ended_at: BillingSegment.inclusive_end(Time.utc(2026, 1, 15))
          )
          expect(operation).not_to be_changed
          expect(operation.reload).to have_attributes(
            action_type: "renew_fixed_advance",
            causation_type: "contract_activation",
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

        expect(result).to have_attributes(segments: be_empty, cycle: be_nil)
      end

      context "when the target cycle starts after contract end" do
        let(:target_cycle_started_at) { Time.utc(2026, 2, 1) }

        it "returns no match after the contract end" do
          result = described_class.call!(operation:)

          expect(result).to have_attributes(segments: be_empty, cycle: be_nil)
        end
      end
    end

    context "when the stored billing date is later than the scheduled one" do
      let(:built_schedules) { [] }
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "renew_fixed_advance", billing_at: Time.utc(2026, 1, 2),
          target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
          billing_interval_count: 1, billing_interval_unit: "month")
        allow(Billing::RateCards::BuildScheduleService).to receive(:call!).and_wrap_original do |original, **attributes|
          original.call(**attributes).tap { built_schedules << it.schedule }
        end
      end

      it "returns the slices of its cycle that fell due before it" do
        result = described_class.call!(operation:)

        expect(result.segments.map { [it.started_at, it.billing_at] }).to eq([[Time.utc(2026, 1, 1), operation.billing_at]])
        expect(Billing::RateCards::BuildScheduleService).to have_received(:call!).with(
          contract_rate_card:
        )
        expect(result.schedule).to be(built_schedules.sole)
      end

      context "when the stored billing date reaches the next cycle" do
        let(:operation) do
          create(:billing_operation, organization:, customer:, contract_rate_card:,
            action_type: "renew_fixed_advance", billing_at: Time.utc(2026, 2, 1),
            target_cycle_started_at: Time.utc(2026, 1, 1))
        end

        it "returns only segments from the stored cycle" do
          result = described_class.call!(operation:)

          expect(result.cycle).to have_attributes(started_at: Time.utc(2026, 1, 1))
          expect(result.segments.map(&:started_at)).to eq([Time.utc(2026, 1, 1)])
        end
      end
    end

    context "when the stored billing date is earlier than the scheduled one" do
      let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 1, 20),
          target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
          billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "returns no segments while keeping the cycle" do
        result = described_class.call!(operation:)

        expect(result).to have_attributes(segments: be_empty, cycle: be_present)
      end
    end

    context "when resolving a termination operation" do
      let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
      let(:contract) do
        create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1),
          status: :terminated, terminated_at: Time.utc(2026, 1, 15))
      end
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "close_fixed_arrears", causation_type: "contract_termination",
          billing_at: Time.utc(2026, 1, 15), target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
          billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "returns the cycle clipped at the termination" do
        result = described_class.call!(operation:)

        expect(result.cycle).to have_attributes(started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 15))
        expect(result.segments.map { [it.started_at, it.ended_at, it.billing_at] }).to eq(
          [[Time.utc(2026, 1, 1), BillingSegment.inclusive_end(Time.utc(2026, 1, 15)), operation.billing_at]]
        )
      end
    end

    context "when the stored cycle is absent from the schedule" do
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "renew_fixed_advance", billing_at: Time.utc(2026, 1, 1),
          target_cycle_started_at: Time.utc(2026, 1, 1))
      end
      let(:schedule) { instance_double(Billing::RateCards::Schedule, cycle_at: nil) }

      before do
        allow(Billing::RateCards::BuildScheduleService).to receive(:call!).and_return(double(schedule:))
      end

      it "returns a successful empty resolution" do
        result = described_class.call!(operation:)

        expect(result).to have_attributes(segments: be_empty, schedule:, cycle: be_nil)
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

      context "when a rate-change reconciliation targets an arrears card" do
        let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
        let(:operation) do
          create(:billing_operation, organization:, customer:, contract_rate_card:,
            action_type: "reconcile_advance_coverage", causation_type: "rate_change",
            billing_at: Time.utc(2026, 1, 15), target_cycle_started_at: Time.utc(2026, 1, 1))
        end

        it "rejects the unsupported action" do
          expect(described_class.call(operation:).error.messages).to eq(operation: ["fixed_advance_reconciliation_unsupported"])
        end
      end
    end

    context "when resolving a supported rate-change reconciliation" do
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "reconcile_advance_coverage", causation_type: "rate_change",
          billing_at: Time.utc(2026, 1, 15), target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      it "returns an empty resolution without requiring priced rates" do
        result = described_class.call!(operation:)

        expect(result).to have_attributes(segments: be_empty, schedule: nil, cycle: nil)
      end
    end

    context "when schedule construction fails" do
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
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
