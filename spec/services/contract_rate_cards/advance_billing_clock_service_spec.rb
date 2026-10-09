# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::AdvanceBillingClockService do
  subject(:result) { described_class.call(contract_rate_card:, schedule:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:contract) { create(:contract, organization:) }
  let(:clock) { Time.zone.parse("2026-03-01 00:00:00") }
  let(:timestamp) { clock }

  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, next_billing_at: clock)
  end

  let(:schedule) { instance_double(Billing::RateCards::Schedule, next_billing_at: next_due) }

  describe "#call" do
    context "when the schedule falls due again later" do
      let(:next_due) { Time.zone.parse("2026-04-01 00:00:00") }

      it "moves the clock to that instant" do
        expect { result }.to change { contract_rate_card.reload.next_billing_at }.from(clock).to(next_due)
      end

      # A catch-up run carries a past instant, and asking the schedule about "now" instead
      # would answer for a period it is not billing.
      it "asks the schedule about the instant it was given" do
        result

        expect(schedule).to have_received(:next_billing_at).with(after: timestamp)
      end
    end

    # Keeping the last instant would have the column claim a billing that never happens, and
    # a null clock never satisfies the producer's due bound, so the card stops being selected.
    context "when the schedule is exhausted" do
      let(:next_due) { nil }

      it "blanks the clock" do
        expect { result }.to change { contract_rate_card.reload.next_billing_at }.from(clock).to(nil)
      end
    end

    # A card can only be born with a clock, so this is a finished schedule that a later
    # change brought back, not a card made wrong.
    context "when the clock is blank and the schedule falls due again" do
      let(:next_due) { Time.zone.parse("2026-04-01 00:00:00") }

      before { contract_rate_card.update!(next_billing_at: nil) }

      it "sets it, there being no earlier period to bill twice" do
        expect { result }.to change { contract_rate_card.reload.next_billing_at }.from(nil).to(next_due)
      end
    end

    # A late run carrying a stale instant asks the schedule what falls due after February,
    # and gets March — earlier than the clock a previous run already moved to April.
    # Rewinding there would bill March a second time.
    context "when the schedule's next due instant precedes the clock" do
      let(:clock) { Time.zone.parse("2026-04-01 00:00:00") }
      let(:timestamp) { Time.zone.parse("2026-02-10 00:00:00") }
      let(:next_due) { Time.zone.parse("2026-03-01 00:00:00") }

      it "leaves the clock where it is" do
        expect { result }.not_to change { contract_rate_card.reload.next_billing_at }
      end
    end
  end
end
