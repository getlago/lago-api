# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::ScheduleService do
  subject(:result) { described_class.call(customer:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: nil) }
  let(:contract) do
    create(:contract, organization:, customer:, started_at: Time.zone.parse("2026-01-01 00:00:00"), ended_at: contract_ended_at)
  end
  let(:contract_ended_at) { nil }
  let(:rate_card) { create(:rate_card, organization:, billing_timing: "arrears", proration: false) }
  let(:timestamp) { Time.zone.parse("2026-03-01 00:00:00") }

  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      rate_card:,
      effective_date: Date.new(2026, 1, 1),
      billing_anchor_date: Date.new(2026, 1, 1),
      next_billing_at: Time.zone.parse("2026-02-01 00:00:00")
    )
  end

  def add_rate(rate_card, effective_from)
    create(
      :rate_card_rate,
      organization:,
      rate_card:,
      effective_from:,
      billing_interval_count: 1,
      billing_interval_unit: "month"
    )
  end

  before do
    add_rate(rate_card, Time.zone.parse("2026-01-01 00:00:00"))
    contract_rate_card
  end

  describe "#call" do
    it "writes the card's due segments" do
      expect(result.billing_segments.map { [it.started_at, it.billing_at] }).to eq(
        [
          [Time.zone.parse("2026-01-01 00:00:00"), Time.zone.parse("2026-02-01 00:00:00")],
          [Time.zone.parse("2026-02-01 00:00:00"), Time.zone.parse("2026-03-01 00:00:00")]
        ]
      )
    end

    it "advances the card's clock past the run" do
      expect { result }
        .to change { contract_rate_card.reload.next_billing_at }
        .to(Time.zone.parse("2026-04-01 00:00:00"))
    end

    it "attaches each segment to its calendar period" do
      expect(result.billing_segments.map { |segment| [segment.billing_cycle.started_at, segment.billing_cycle.ended_at] })
        .to eq([
          [Time.utc(2026, 1, 1), Time.utc(2026, 2, 1)],
          [Time.utc(2026, 2, 1), Time.utc(2026, 3, 1)]
        ])
    end

    context "with multiple rate changes in the same cycle" do
      before do
        add_rate(rate_card, Time.utc(2026, 2, 11))
        add_rate(rate_card, Time.utc(2026, 2, 21))
      end

      it "keeps all pricing slices on one cycle" do
        segments = result.billing_segments.select { |segment| segment.cycle_started_at == Time.utc(2026, 2, 1) }

        expect(segments.map(&:started_at)).to eq([Time.utc(2026, 2, 1), Time.utc(2026, 2, 11), Time.utc(2026, 2, 21)])
        expect(segments.map(&:billing_cycle_id).uniq.size).to eq(1)
        expect(segments.first.billing_cycle).to have_attributes(
          started_at: Time.utc(2026, 2, 1), ended_at: Time.utc(2026, 3, 1)
        )
      end

      it "reuses the cycle when its slices become due in separate runs" do
        first = described_class.call!(customer:, timestamp: Time.utc(2026, 2, 11))
          .billing_segments.find { |segment| segment.cycle_started_at == Time.utc(2026, 2, 1) }

        expect { result }.not_to change(BillingCycle, :count)
        expect(result.billing_segments.map(&:billing_cycle_id)).to eq([first.billing_cycle_id, first.billing_cycle_id])
      end
    end

    context "when the contract ends before the nominal cycle boundary" do
      let(:contract_ended_at) { Time.utc(2026, 2, 11) }

      it "limits the billed service without shortening the calendar reference" do
        segment = result.billing_segments.last

        expect(segment.ended_at).to eq(BillingSegment.inclusive_end(contract_ended_at))
        expect(segment.billing_cycle).to have_attributes(
          started_at: Time.utc(2026, 2, 1),
          reference_started_at: Time.utc(2026, 2, 1),
          ended_at: Time.utc(2026, 3, 1)
        )
      end
    end

    it "is idempotent: a second run writes nothing more" do
      result
      expect { described_class.call(customer:, timestamp:) }.not_to change(BillingSegment, :count)
    end

    # The clock is the only trigger. A rate added before the saved clock splits a cycle and
    # makes a slice due earlier, and this producer does not discover it: the slice is written
    # on the next tick the clock does reach, carrying its own earlier billing_at. Pulling the
    # clock back is the mutating path's job, as it is for termination.
    context "when a rate is added before the saved clock" do
      before do
        add_rate(rate_card, Time.zone.parse("2026-02-15 00:00:00"))
        contract_rate_card.update!(next_billing_at: Time.zone.parse("2026-03-01 00:00:00"))
      end

      it "writes nothing at the new billing time, because the clock has not come due" do
        expect(described_class.call(customer:, timestamp: Time.zone.parse("2026-02-20 00:00:00")).billing_segments)
          .to be_empty
      end

      it "writes the slice late, on the tick the clock does reach, keeping its own billing date" do
        late = result.billing_segments.find { it.billing_at == Time.zone.parse("2026-02-15 00:00:00") }

        expect(late).to have_attributes(started_at: Time.zone.parse("2026-02-01 00:00:00"))
      end
    end

    # An advance cycle already billed in full, then a rate added inside it. The cycle is
    # settled at the price it was billed at, and the run must carry on to the next one
    # rather than stall on the overlap with the stored segment.
    context "when a rate lands inside an already-billed advance cycle" do
      let(:rate_card) { create(:rate_card, organization:, billing_timing: "advance", proration: false) }

      before do
        described_class.call!(customer:, timestamp: Time.zone.parse("2026-02-01 00:00:00"))
        add_rate(rate_card, Time.zone.parse("2026-02-10 00:00:00"))
      end

      it "bills the next cycle instead of failing" do
        expect(result.billing_segments.map(&:started_at)).to eq([Time.zone.parse("2026-03-01 00:00:00")])
      end

      it "leaves the settled cycle untouched" do
        expect { result }.not_to change {
          BillingSegment.where(customer:, started_at: Time.zone.parse("2026-02-01 00:00:00")).pick(:ended_at)
        }
      end
    end

    # Not the skip above: an unpriced card never reaches the loop, the selection leaves it out.
    # Kept end to end because it is the common shape — a card is attached before it is priced.
    context "when another card of the same customer has no price yet" do
      let(:unpriced_card) do
        create(
          :contract_rate_card,
          organization:,
          contract:,
          rate_card: create(:rate_card, organization:, billing_timing: "arrears"),
          effective_date: Date.new(2026, 1, 1),
          billing_anchor_date: Date.new(2026, 1, 1),
          next_billing_at: Time.zone.parse("2026-02-01 00:00:00")
        )
      end

      before { unpriced_card }

      it "bills the priced card and never considers the unpriced one" do
        expect(result.billing_segments.map(&:contract_rate_card_id).uniq).to eq([contract_rate_card.id])
      end

      it "leaves the unpriced card's clock alone, so it bills once it has a price" do
        expect { result }.not_to change { unpriced_card.reload.next_billing_at }
      end
    end

    # MissingBillableSegmentsService keeps overlapping candidates out, so this is the last-resort
    # guard behind it: a concurrent writer, or a path that writes without that filter.
    # The filter is stubbed out here to reach it.
    context "when an overlapping segment reaches the database" do
      before do
        allow(BillingSegments::MissingBillableSegmentsService).to receive(:call!) do |contract_rate_card:, schedule:, timestamp:|
          BillingSegments::MissingBillableSegmentsService::Result.new.tap do |unfiltered|
            unfiltered.billable_segments = schedule.segments_due_by(timestamp)
          end
        end

        create(
          :billing_segment,
          organization:,
          customer:,
          contract:,
          contract_rate_card:,
          rate_card_rate: rate_card.rates.first,
          # Anchored on January so the walker still replays that cycle, but covering only
          # February: the run writes January, then trips on the piece that overlaps.
          cycle_started_at: Time.zone.parse("2026-01-01 00:00:00"),
          started_at: Time.zone.parse("2026-02-05 00:00:00"),
          ended_at: BillingSegment.inclusive_end(Time.zone.parse("2026-02-20 00:00:00")),
          billing_at: Time.zone.parse("2026-02-20 00:00:00")
        )
      end

      it "reports the conflict instead of raising" do
        expect(result.error.messages).to eq({billing_segment: ["overlapping_periods"]})
      end

      it "writes nothing" do
        expect { result }.not_to change(BillingSegment, :count)
      end

      it "rolls back the cycles together with the failed segments" do
        expect { result }.not_to change(BillingCycle, :count)
      end

      it "reports no segments, the rollback having undone the ones it had built" do
        expect(result.billing_segments).to eq([])
      end
    end
  end
end
