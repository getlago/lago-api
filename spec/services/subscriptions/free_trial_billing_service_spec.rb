# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::FreeTrialBillingService do
  subject(:service) { described_class.new(timestamp:) }

  let(:timestamp) { Time.zone.now }

  describe "#call" do
    let(:plan) { create(:plan, trial_period: 10, pay_in_advance: true) }

    context "with a plan witout trial period" do
      it "does not set trial_ended_at" do
        sub = create(:subscription, plan: create(:plan, trial_period: 0, pay_in_advance: true), started_at: 2.days.ago)
        sub2 = create(:subscription, plan: create(:plan, pay_in_advance: true), started_at: 2.days.ago)
        service.call
        expect(sub.reload.trial_ended_at).to be_nil
        expect(sub2.reload.trial_ended_at).to be_nil
      end
    end

    context "without any ending trial subscriptions" do
      it "does not set trial_ended_at" do
        sub1 = create(:subscription, plan:, started_at: 2.days.ago)

        expect { service.call }.not_to change { sub1.reload.trial_ended_at }.from(nil)
      end
    end

    context "with ending trial subscriptions" do
      it "sets trial_ended_at to trial end date" do
        sub = create(:subscription, plan:, started_at: Time.zone.parse("2024-04-05T12:12:00"))
        sub2 = create(:subscription, plan:, started_at: 15.days.ago)
        service.call
        expect(sub.reload.trial_ended_at).to match_datetime(sub.trial_end_datetime)
        expect(sub2.reload.trial_ended_at).to match_datetime(sub2.trial_end_datetime)
      end
    end

    context "with trial ended due to previous subscription with the same external_id" do
      it "sets trial_ended_at" do
        customer = create(:customer)
        attr = {customer:, plan:, external_id: "abc123"}
        started_at = timestamp - 10.days - 1.hour
        create(:subscription, started_at:, terminated_at: 6.days.ago, status: :terminated, **attr)
        sub = create(:subscription, started_at: 6.days.ago, **attr)

        expect { service.call }.to change { sub.reload.trial_ended_at }.from(nil).to(sub.trial_end_datetime)
      end
    end

    context "with customer timezone" do
      let(:timestamp) { DateTime.parse("2024-03-11 13:03:00 UTC") }

      it "sets trial_ended_at to the expected subscription (timezone is irrelevant)" do
        started_at = DateTime.parse("2024-03-01 12:00:00 UTC")
        customer = create(:customer, timezone: "America/Los_Angeles")
        sub = create(:subscription, plan:, customer:, started_at:)
        service.call
        expect(sub.reload.trial_ended_at).to match_datetime(sub.trial_end_datetime)
      end
    end

    context "when the subscription should sync with Hubspot" do
      it "calls the Hubspot update job" do
        customer = create(:customer, :with_hubspot_integration)
        plan = create(:plan, trial_period: 10, pay_in_advance: true)
        subscription = create(:subscription, customer:, plan:, started_at: 15.days.ago)
        service.call
        expect(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob)
          .to have_been_enqueued.with(subscription: subscription)
      end
    end

    context "with plan pay in arrears" do
      let(:plan) { create(:plan, trial_period: 10, pay_in_advance: false) }

      context "when plan has fixed charges" do
        context "when fixed_charges are not pay in advance" do
          let(:fixed_charge) { create(:fixed_charge, plan:, pay_in_advance: false) }
          let(:subscription) { create(:subscription, plan:, started_at: 11.days.ago) }

          before do
            fixed_charge
            subscription
          end

          it "does not enqueue a job to bill the subscription" do
            expect { service.call }.not_to have_enqueued_job(BillSubscriptionJob)
          end
        end

        context "when fixed_charges are pay in advance" do
          let(:fixed_charge) { create(:fixed_charge, plan:, pay_in_advance: true) }
          let(:subscription) { create(:subscription, plan:, started_at: 11.days.ago) }

          before do
            fixed_charge
            subscription
          end

          it "does not enqueue a job to bill the subscription" do
            expect { service.call }.not_to have_enqueued_job(BillSubscriptionJob)
          end
        end
      end
    end

    context "with plan pay in advance" do
      let(:plan) { create(:plan, trial_period: 10, pay_in_advance: true) }

      context "when plan has fixed charges" do
        context "when fixed_charges are not pay in advance" do
          let(:fixed_charge) { create(:fixed_charge, plan:, pay_in_advance: false) }
          let(:subscription) { create(:subscription, plan:, started_at: 11.days.ago) }

          before do
            fixed_charge
            subscription
          end

          it "enqueues a job to bill the subscription" do
            expect { service.call }.to have_enqueued_job(BillSubscriptionJob)
          end
        end
      end
    end

    context "when the trial ends late in the customer's local day" do
      let(:plan) { create(:plan, trial_period: 41, pay_in_advance: true) }
      let(:customer) { create(:customer, timezone: "Europe/Ljubljana") }

      # Started Jun 15 23:47 local (21:47 UTC, CEST is UTC+2). With a 41 day trial, Jul 26 is the
      # first paid day: Fees::SubscriptionService prorates the subscription fee from the trial end
      # DATE, charging the whole of Jul 26. Billing must therefore happen on Jul 26 in the customer
      # timezone, not once the exact signup time of day has passed (which pushes the invoice to
      # Jul 27 for signups late in the local day).
      let(:subscription) do
        create(:subscription, plan:, customer:, started_at: Time.zone.parse("2026-06-15 21:47:00 UTC"))
      end

      before { subscription }

      context "with the first hourly tick of the trial end date in the customer timezone" do
        let(:timestamp) { Time.zone.parse("2026-07-25 22:35:00 UTC") } # Jul 26 00:35 local

        it "bills the subscription and ends the trial on the trial end date" do
          expect { service.call }.to have_enqueued_job(BillSubscriptionJob)
          expect(subscription.reload.trial_ended_at).not_to be_nil
        end
      end

      context "with a tick on the day before the trial end date in the customer timezone" do
        let(:timestamp) { Time.zone.parse("2026-07-25 21:35:00 UTC") } # Jul 25 23:35 local

        it "does not bill and keeps the trial running" do
          expect { service.call }.not_to have_enqueued_job(BillSubscriptionJob)
          expect(subscription.reload.trial_ended_at).to be_nil
        end
      end
    end
  end
end
