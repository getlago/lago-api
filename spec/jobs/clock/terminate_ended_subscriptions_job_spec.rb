# frozen_string_literal: true

require "rails_helper"

describe Clock::TerminateEndedSubscriptionsJob, job: true do
  subject { described_class }

  let(:ending_at) { (Time.current + 2.months).beginning_of_day }
  let!(:subscription1) { create(:subscription, ending_at:) }
  let!(:subscription2) { create(:subscription, ending_at: ending_at + 1.year) }
  let!(:subscription3) { create(:subscription, ending_at: nil) }

  describe ".perform" do
    before do
      allow(Subscriptions::TerminateService).to receive(:call)
    end

    it "terminates the subscriptions where ending_at matches current data" do
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

  describe "when lock errors occur" do
    let!(:subscription4) { create(:subscription, ending_at:) }

    [
      Customers::FailedToAcquireLock.new("customer-1-prepaid_credit"),
      ActiveRecord::StaleObjectError.new("Attempted to update a stale object: Wallet.")
    ].each do |error|
      error_class = error.class

      context "when a #{error_class} error is raised" do
        before do
          allow(Subscriptions::TerminateService).to receive(:call)
            .with(subscription: subscription1).and_raise(error)
          allow(Subscriptions::TerminateService).to receive(:call)
            .with(subscription: subscription4)
        end

        it "enqueues a TerminateEndedSubscriptionJob with a delay for the failed subscription" do
          current_date = Time.current + 2.months

          travel_to(current_date) do
            described_class.perform_now

            expect(Subscriptions::TerminateEndedSubscriptionJob)
              .to have_been_enqueued
              .with(subscription: subscription1)
          end
        end

        it "does not raise error" do
          current_date = Time.current + 2.months

          travel_to(current_date) do
            expect { described_class.perform_now }.not_to raise_error
          end
        end

        it "continues processing remaining subscriptions" do
          current_date = Time.current + 2.months

          travel_to(current_date) do
            described_class.perform_now

            expect(Subscriptions::TerminateService)
              .to have_received(:call).with(subscription: subscription4)
          end
        end
      end
    end
  end
end
