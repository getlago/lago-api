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

  describe "retry_on" do
    [
      [Customers::FailedToAcquireLock.new("customer-1-prepaid_credit"), 25],
      [ActiveRecord::StaleObjectError.new("Attempted to update a stale object: Wallet."), 25]
    ].each do |error, attempts|
      error_class = error.class

      context "when a #{error_class} error is raised" do
        before do
          allow(Subscriptions::TerminateService).to receive(:call).and_raise(error)
        end

        it "raises a #{error_class.class.name} error and retries" do
          current_date = Time.current + 2.months

          travel_to(current_date) do
            assert_performed_jobs(attempts, only: [described_class]) do
              expect do
                described_class.perform_later
              end.to raise_error(error_class)
            end
          end
        end
      end
    end
  end
end
