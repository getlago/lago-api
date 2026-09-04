# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::BaseStore do
  describe "#period_duration" do
    subject(:period_duration) { store.send(:period_duration) }

    let(:subscription) { create(:subscription) }
    let(:store) do
      described_class.new(
        context:,
        boundaries: {
          from_datetime: Time.zone.parse("2026-03-01"),
          to_datetime: Time.zone.parse("2026-03-31").end_of_day,
          charges_duration: 30
        }
      )
    end
    let(:context) { Events::Stores::EventContext.from(subscription:) }

    it "computes duration through the event context" do
      allow(context).to receive(:charges_duration_at).and_return(31)

      expect(period_duration).to eq(31)
      expect(context).to have_received(:charges_duration_at)
        .with(Time.zone.parse("2026-03-31").end_of_day + 1.day)
    end

    it "uses the explicit boundary duration for the charges duration" do
      expect(store.charges_duration).to eq(30)
    end

    context "when context is contract-backed" do
      let(:context) { Events::Stores::EventContext.from(contract: create(:contract)) }

      it "raises when duration is requested" do
        expect { period_duration }
          .to raise_error(NotImplementedError, "contract-backed event contexts do not have charge durations yet")
      end
    end
  end
end
