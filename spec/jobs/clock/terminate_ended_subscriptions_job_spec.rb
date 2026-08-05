# frozen_string_literal: true

require "rails_helper"

describe Clock::TerminateEndedSubscriptionsJob, job: true do
  subject { described_class }

  let(:ending_at) { (Time.current + 2.months).beginning_of_day }
  let!(:subscription1) { create(:subscription, ending_at:) }
  let!(:subscription2) { create(:subscription, ending_at: ending_at + 1.year) }
  let!(:subscription3) { create(:subscription, ending_at: nil) }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  describe ".perform" do
    it "enqueues a TerminateEndedSubscriptionJob for subscriptions past their ending_at" do
      current_date = Time.current + 2.months

      travel_to(current_date) do
        described_class.perform_now

        expect(Subscriptions::TerminateEndedSubscriptionJob)
          .to have_been_enqueued.with(subscription1)
        expect(Subscriptions::TerminateEndedSubscriptionJob)
          .not_to have_been_enqueued.with(subscription2)
        expect(Subscriptions::TerminateEndedSubscriptionJob)
          .not_to have_been_enqueued.with(subscription3)
      end
    end

    context "when the subscription ends later in the day" do
      # ending_at is at 15:00, so the midnight run must NOT terminate it yet.
      let(:ending_at) { DateTime.parse("2026-10-21 15:00:00") }

      it "does not terminate it when the clock runs before ending_at (e.g. midnight)" do
        travel_to(DateTime.parse("2026-10-21 00:05:00")) do
          described_class.perform_now

          expect(Subscriptions::TerminateEndedSubscriptionJob)
            .not_to have_been_enqueued.with(subscription1)
        end
      end

      it "terminates it on the next hourly run after ending_at has passed" do
        travel_to(DateTime.parse("2026-10-21 15:05:00")) do
          described_class.perform_now

          expect(Subscriptions::TerminateEndedSubscriptionJob)
            .to have_been_enqueued.with(subscription1)
        end
      end
    end
  end
end
