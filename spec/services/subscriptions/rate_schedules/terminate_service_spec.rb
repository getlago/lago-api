# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::RateSchedules::TerminateService do
  subject(:terminate_service) { described_class.new(subscription:) }

  let(:on_termination_credit_note) { nil }

  describe "#call" do
    subject(:result) { described_class.call(subscription:, on_termination_credit_note:) }

    let(:organization) { create(:organization) }
    let(:plan) { create(:plan, organization:) }
    let(:product) { create(:product, organization:) }
    let(:product_item) { create(:product_item, :subscription, product:, organization:) }
    let(:plan_product_item) { create(:plan_product_item, plan:, product_item:, organization:) }

    let(:rate_schedule) { create(:rate_schedule, plan_product_item:, organization:) }

    let(:subscription) { create(:subscription, plan:) }
    let(:subscription_rate_schedule) { create(:subscription_rate_schedule, subscription:, product_item:, rate_schedule:, organization:) }

    before do
      subscription_rate_schedule
      allow(Utils::ActivityLog).to receive(:produce_after_commit)
    end

    it "sends subscription.terminated webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.terminated", subscription)
    end

    it "logs subscription.terminated event" do
      subject
      expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(subscription, "subscription.terminated")
    end

    context "when subscription starts in the future" do
      let(:subscription) { create(:subscription, :pending, plan:) }

      it "cancels the subscription" do
        result = subject

        expect(result.subscription).to be_present
        expect(result.subscription).to be_canceled
        expect(result.subscription.canceled_at).to be_present
        expect(result.subscription.terminated_at).to be_nil
      end

      it "does not enqueue a Invoices::RateSchedulesBillingJob" do
        expect { subject }.not_to have_enqueued_job(Invoices::RateSchedulesBillingJob)
      end

      it "does not send subscription.updated webhook" do
        expect { subject }.not_to have_enqueued_job(SendWebhookJob).with("subscription.updated", subscription)
      end
    end

    context "when subscription is pending downgraded" do
      let(:subscription) { create(:subscription, :pending, plan:, previous_subscription:) }
      let(:previous_subscription) { create(:subscription) }

      it "cancels the subscription" do
        result = subject

        expect(result.subscription).to be_present
        expect(result.subscription).to be_canceled
        expect(result.subscription.canceled_at).to be_present
        expect(result.subscription.terminated_at).to be_nil
      end

      it "sends both subscription.terminated for the canceled and subscription.updated for the previous subscription" do
        subject

        expect(SendWebhookJob).to have_been_enqueued.with("subscription.terminated", subscription)
        expect(SendWebhookJob).to have_been_enqueued.with("subscription.updated", previous_subscription)
      end
    end

    context "when subscription is active" do
      it "terminates the subscription" do
        subject

        expect(result).to be_a(BaseResult)
        expect(result).to be_success
        expect(result.subscription).to be_present
        expect(result.subscription).to be_terminated
        expect(result.subscription.terminated_at).to be_present
      end

      it "does not create a credit note for the remaining days" do
        expect { subject }.not_to change(CreditNote, :count)
      end

      it "bills the subscription" do
        freeze_time do
          expect { subject }.to have_enqueued_job_after_commit(Invoices::RateSchedulesBillingJob).
            with([subscription_rate_schedule], Time.current, invoicing_reason: :subscription_terminating)
        end
      end
    end

    context "when subscription should be synced with Hubspot" do
      let(:customer) { create(:customer, :with_hubspot_integration) }
      let(:subscription) { create(:subscription, customer:, plan:) }

      it "syncs the subscription with Hubspot" do
        expect { subject }.to have_enqueued_job_after_commit(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob).with(subscription:).twice
      end
    end

    context "with :on_termination_invoice parameter" do
      subject(:result) { described_class.call(subscription:, on_termination_invoice:) }

      context "and on_termination_invoice is :generate" do
        let(:on_termination_invoice) { "generate" }

        it "updates the subscription :on_termination_invoice value" do
          subject
          expect(subscription.reload.on_termination_invoice).to eq("generate")
        end

        it "bills the subscription" do
          freeze_time do
            expect { subject }.to have_enqueued_job_after_commit(Invoices::RateSchedulesBillingJob)
              .with([subscription_rate_schedule], Time.current, invoicing_reason: :subscription_terminating)
          end
        end
      end

      context "and on_termination_invoice is :skip" do
        let(:on_termination_invoice) { "skip" }

        it "updates the subscription :on_termination_invoice value" do
          subject
          expect(subscription.reload.on_termination_invoice).to eq("skip")
        end

        it "does not bill the subscription" do
          expect { subject }.not_to have_enqueued_job(Invoices::RateSchedulesBillingJob)
        end
      end

      context "and :on_termination_invoice is invalid" do
        let(:on_termination_invoice) { "invalid" }

        it "raises an error" do
          subject

          expect(result).to be_failure
          expect(result.error.messages).to include({on_termination_invoice: ["invalid_value"]})
        end
      end
    end

    xcontext "with :on_termination_credit_note parameter" do
      let(:subscription) do
        create(
          :subscription,
          :anniversary,
          plan:,
          started_at: creation_time,
          subscription_at: creation_time
        )
      end
      let(:rate_schedule) { create(:rate_schedule, :pay_in_advance, plan_product_item:, organization:) }
      let(:creation_time) { Time.current.beginning_of_month - 1.month }
      let(:date_service) do
        Subscriptions::DatesService.new_instance(
          subscription,
          Time.current.beginning_of_month,
          current_usage: false
        )
      end
      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          invoice:,
          subscription:,
          recurring: true,
          from_datetime: date_service.from_datetime,
          to_datetime: date_service.to_datetime,
          charges_from_datetime: date_service.charges_from_datetime,
          charges_to_datetime: date_service.charges_to_datetime
        )
      end
      let(:invoice) do
        create(
          :invoice,
          customer: subscription.customer,
          currency: "EUR",
          sub_total_excluding_taxes_amount_cents: 100,
          fees_amount_cents: 100,
          taxes_amount_cents: 20,
          total_amount_cents: 120
        )
      end

      let(:last_subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 100,
          taxes_amount_cents: 20,
          invoiceable_type: "Subscription",
          invoiceable_id: subscription.id,
          taxes_rate: 20
        )
      end

      before do
        invoice_subscription
        last_subscription_fee
      end

      [nil, "", "credit"].each do |on_termination_credit_note|
        context "when on_termination_credit_note is #{on_termination_credit_note.inspect}" do
          let(:on_termination_credit_note) { on_termination_credit_note }

          it "creates a credit note for the remaining days" do
            travel_to(Time.current.end_of_month - 4.days) do
              expect { subject }.to change(CreditNote, :count).by(1)
            end
          end

          it "updates subscription.on_termination_credit_note value" do
            travel_to(Time.current.end_of_month - 4.days) do
              subject
              expect(subscription.reload.on_termination_credit_note).to eq("credit")
            end
          end
        end
      end

      context "when on_termination_credit_note is :skip" do
        let(:on_termination_credit_note) { "skip" }

        it "does not create a credit note for the remaining days" do
          travel_to(Time.current.end_of_month - 4.days) do
            expect { subject }.not_to change(CreditNote, :count)
          end
        end

        it "updates subscription.on_termination_credit_note value" do
          travel_to(Time.current.end_of_month - 4.days) do
            subject
            expect(subscription.reload.on_termination_credit_note).to eq("skip")
          end
        end
      end

      context "when on_termination_credit_note is :refund" do
        let(:on_termination_credit_note) { "refund" }

        it "creates a credit note for the remaining days with refund" do
          travel_to(Time.current.end_of_month - 4.days) do
            expect { subject }.to change(CreditNote, :count).by(1)
          end
        end

        it "updates subscription.on_termination_credit_note value" do
          travel_to(Time.current.end_of_month - 4.days) do
            subject
            expect(subscription.reload.on_termination_credit_note).to eq("refund")
          end
        end
      end

      context "when on_termination_credit_note is :offset" do
        let(:on_termination_credit_note) { "offset" }

        it "creates a credit note for the remaining days with offset" do
          travel_to(Time.current.end_of_month - 4.days) do
            expect { subject }.to change(CreditNote, :count).by(1)
          end
        end

        it "updates subscription.on_termination_credit_note value" do
          travel_to(Time.current.end_of_month - 4.days) do
            subject
            expect(subscription.reload.on_termination_credit_note).to eq("offset")
          end
        end
      end

      context "when on_termination_credit_note is not set" do
        subject(:result) { described_class.call(subscription:) }

        it "does not create a credit note for the remaining days" do
          travel_to(Time.current.end_of_month - 4.days) do
            expect { subject }.not_to change(CreditNote, :count)
          end
        end
      end

      context "when on_termination_credit_note is invalid" do
        let(:on_termination_credit_note) { "invalid" }

        it "raises an error" do
          subject

          expect(result).to be_failure
          expect(result.error.messages).to include({on_termination_credit_note: ["invalid_value"]})
        end
      end

      context "when invoice subscription is not generated" do
        let(:invoice_subscription) { nil }

        it "does not create a credit note for the remaining days" do
          expect { subject }.not_to change(CreditNote, :count)
        end
      end

      context "and the subscription is pay in arrears" do
        let(:on_termination_credit_note) { "credit" }

        before do
          rate_schedule.update!(pay_in_advance: false)
        end

        it "does not create a credit note" do
          expect { subject }.not_to change(CreditNote, :count)
        end

        it "updates subscription.on_termination_credit_note value" do
          subject
          expect(subscription.reload.on_termination_credit_note).to eq(nil)
        end
      end
    end

    context "when next subscription is pending" do
      let(:next_subscription) do
        create(
          :subscription,
          previous_subscription: subscription,
          plan:,
          status: :pending
        )
      end

      before { next_subscription }

      it "cancels the next subscription" do
        subject

        expect(result).to be_success
        expect(next_subscription.reload).to be_canceled
      end
    end

    context "when subscription is not found" do
      let(:subscription) { nil }
      let(:subscription_rate_schedule) { nil }

      it "returns an error" do
        subject

        expect(result.error.error_code).to eq("subscription_not_found")
      end
    end
  end
end
