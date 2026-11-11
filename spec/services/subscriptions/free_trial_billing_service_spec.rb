# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::FreeTrialBillingService do
  subject(:service) { described_class.new(timestamp:) }

  before_all do
    create_default(:organization)
  end

  let(:timestamp) { Time.zone.now }

  describe "#call" do
    let_it_be(:plan, refind: true) { create(:plan, trial_period: 10, pay_in_advance: true) }

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

    context "with an older subscription of another organization sharing the external_id" do
      it "does not set trial_ended_at" do
        other_organization = create(:organization)
        create(
          :subscription,
          :terminated,
          customer: create(:customer, organization: other_organization),
          plan: create(:plan, organization: other_organization, trial_period: 10),
          external_id: "abc123",
          started_at: 30.days.ago
        )
        sub = create(:subscription, plan:, external_id: "abc123", started_at: 2.days.ago)

        expect { service.call }.not_to change { sub.reload.trial_ended_at }.from(nil)
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
      let_it_be(:plan, refind: true) { create(:plan, trial_period: 10, pay_in_advance: false) }

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

      context "with several previous subscriptions sharing the external_id" do
        it "bills the subscription and announces the trial end once" do
          attributes = {customer: create(:customer), plan:, external_id: "abc123"}
          create(:subscription, :terminated, started_at: 20.days.ago, terminated_at: 15.days.ago, **attributes)
          create(:subscription, :terminated, started_at: 15.days.ago, terminated_at: 5.days.ago, **attributes)
          subscription = create(:subscription, started_at: 5.days.ago, **attributes)

          expect { service.call }
            .to have_enqueued_job(BillSubscriptionJob).exactly(:once)
            .and have_enqueued_job(SendWebhookJob).with("subscription.trial_ended", subscription).exactly(:once)
        end
      end

      context "with a recurring invoice issued around the trial end" do
        # NOTE: The trial ends on 2024-11-01 at 23:40 UTC, the job runs the next day
        let(:timestamp) { Time.zone.parse("2024-11-02T00:35:00") }
        let(:timezone) { nil }
        let(:customer) { create(:customer, timezone:) }
        let(:subscription) { create(:subscription, plan:, customer:, started_at: Time.zone.parse("2024-10-22T23:40:00")) }
        let(:recurring) { true }

        before do
          create(:invoice_subscription, subscription:, invoice: create(:invoice, customer:), recurring:, timestamp: invoice_timestamp)
        end

        context "when it was issued on the trial end day" do
          let(:invoice_timestamp) { Time.zone.parse("2024-11-01T00:10:00") }

          it "does not bill the subscription again" do
            expect { service.call }.not_to have_enqueued_job(BillSubscriptionJob)
            expect(subscription.reload.trial_ended_at).to match_datetime(subscription.trial_end_datetime)
          end
        end

        context "when it was issued on the run day" do
          let(:invoice_timestamp) { Time.zone.parse("2024-11-02T00:10:00") }

          it "does not bill the subscription again" do
            expect { service.call }.not_to have_enqueued_job(BillSubscriptionJob)
          end
        end

        context "when it was issued before the trial end day" do
          let(:invoice_timestamp) { Time.zone.parse("2024-10-31T00:10:00") }

          it "bills the subscription" do
            expect { service.call }.to have_enqueued_job(BillSubscriptionJob)
          end
        end

        context "when it is not recurring" do
          let(:invoice_timestamp) { Time.zone.parse("2024-11-01T00:10:00") }
          let(:recurring) { false }

          it "bills the subscription" do
            expect { service.call }.to have_enqueued_job(BillSubscriptionJob)
          end
        end

        context "with a customer timezone" do
          # NOTE: 2024-11-01T23:40 UTC is 2024-11-02T00:40 in Paris, so the trial ends on Nov 2 locally
          let(:timezone) { "Europe/Paris" }

          context "when it was issued on the trial end day in the customer timezone" do
            let(:invoice_timestamp) { Time.zone.parse("2024-11-01T23:10:00") } # 2024-11-02T00:10 Paris

            it "does not bill the subscription again" do
              expect { service.call }.not_to have_enqueued_job(BillSubscriptionJob)
            end
          end

          context "when it was issued the day before in the customer timezone" do
            let(:invoice_timestamp) { Time.zone.parse("2024-11-01T00:10:00") } # 2024-11-01T01:10 Paris

            it "bills the subscription" do
              expect { service.call }.to have_enqueued_job(BillSubscriptionJob)
            end
          end
        end
      end
    end
  end
end
