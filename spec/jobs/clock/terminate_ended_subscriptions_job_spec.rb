# frozen_string_literal: true

require "rails_helper"

describe Clock::TerminateEndedSubscriptionsJob, job: true do
  subject { described_class }

  describe ".perform" do
    let(:ending_at) { (Time.current + 2.months).beginning_of_day }
    let(:subscription1) { create(:subscription, ending_at:) }
    let(:subscription2) { create(:subscription, ending_at: ending_at + 1.year) }
    let(:subscription3) { create(:subscription, ending_at: nil) }

    before do
      subscription1
      subscription2
      subscription3
      allow(Subscriptions::TerminateService).to receive(:call)
    end

    it "terminates the subscriptions where ending_at matches current data " do
      current_date = Time.current + 2.months

      travel_to(current_date) do
        described_class.perform_now
        expect(Subscriptions::TerminateService)
          .to have_received(:call).with(subscription: subscription1)
        expect(Subscriptions::TerminateService)
          .not_to have_received(:call).with(subscription: subscription2)
        expect(Subscriptions::TerminateService)
          .not_to have_received(:call).with(subscription: subscription3)
      end
    end

    context "with customer timezone" do
      let(:ending_at) { DateTime.parse("2022-10-21 00:30:00") }

      before do
        subscription1.customer.update!(timezone: "America/New_York")
      end

      it "takes timezone into account" do
        current_date = ending_at

        travel_to(current_date) do
          described_class.perform_now
          expect(Subscriptions::TerminateService)
            .to have_received(:call).with(subscription: subscription1)
          expect(Subscriptions::TerminateService)
            .not_to have_received(:call).with(subscription: subscription2)
          expect(Subscriptions::TerminateService)
            .not_to have_received(:call).with(subscription: subscription3)
        end
      end
    end
  end
end
