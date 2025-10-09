# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::OrganizationBillingService do
  subject(:billing_service) { described_class.new(organization:, billing_at:) }

  describe ".call" do
    let(:organization) { create(:organization) }
    let(:plan) { create(:plan, organization:, interval:, bill_charges_monthly:) }
    let(:bill_charges_monthly) { false }
    let(:created_at) { DateTime.parse("20 Feb 2020") }
    let(:subscription_at) { DateTime.parse("20 Feb 2021") }
    let(:customer) { create(:customer, organization:) }
    let(:customer2) { create(:customer, organization:) }

    let(:subscription) do
      create(
        :subscription,
        customer: customer2,
        plan:,
        subscription_at:,
        started_at: current_date - 10.days,
        billing_time:,
        created_at:
      )
    end

    let(:current_date) { DateTime.parse("20 Jun 2022") }
    let(:billing_at) { current_date }

    before { subscription }

    context "when billed weekly with calendar billing time" do
      let(:interval) { :weekly }
      let(:billing_time) { :calendar }

      let(:subscription1) do
        create(
          :subscription,
          customer:,
          plan:,
          subscription_at:,
          started_at: current_date - 10.days,
          created_at:
        )
      end

      let(:subscription2) do
        create(
          :subscription,
          customer:,
          plan:,
          subscription_at:,
          started_at: current_date - 10.days,
          created_at:
        )
      end

      let(:customer3) { create(:customer, organization:) }

      let(:subscription3) do
        create(
          :subscription,
          customer: customer3,
          plan:,
          subscription_at:,
          started_at: current_date - 10.days,
          created_at:
        )
      end

      before do
        subscription1
        subscription2
        subscription3
      end

      it "enqueues a job on billing day" do
        billing_service.call

        expect(BillSubscriptionJob).to have_been_enqueued
          .with(
            contain_exactly(subscription1, subscription2),
            current_date.to_i,
            invoicing_reason: :subscription_periodic
          )

        expect(BillNonInvoiceableFeesJob).to have_been_enqueued
          .with(
            contain_exactly(subscription1, subscription2),
            current_date
          )

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription3], current_date.to_i, invoicing_reason: :subscription_periodic)
        expect(BillNonInvoiceableFeesJob).to have_been_enqueued
          .with([subscription3], current_date)
      end

      context "when billing_at is another day" do
        let(:billing_at) { DateTime.parse("21 Jun 2022") }

        it "does not enqueue a job on other day" do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end
    end

    context "when billed monthly with calendar billing time" do
      let(:interval) { :monthly }
      let(:billing_time) { :calendar }
      let(:current_date) { DateTime.parse("01 Feb 2022") }

      it "enqueues a job on billing day" do
        billing_service.call

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)

        expect(BillNonInvoiceableFeesJob).to have_been_enqueued.with([subscription], current_date)
      end

      context "when billing_at is different" do
        let(:billing_at) { DateTime.parse("02 Feb 2022") }

        it "does not enqueue a job on other day" do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context "when ending_at is the same as billing day" do
        let(:billing_date) { DateTime.parse("01 Feb 2022") }
        let(:subscription) do
          create(
            :subscription,
            plan:,
            subscription_at:,
            started_at: subscription_at,
            billing_time:,
            ending_at: billing_date
          )
        end

        it "does not enqueue a job on billing day" do
          billing_service.call

          expect(BillSubscriptionJob).not_to have_been_enqueued
            .with([subscription], billing_date.to_i, invoicing_reason: :subscription_periodic)
          expect(BillNonInvoiceableFeesJob).not_to have_been_enqueued
            .with([subscription], billing_date)
        end
      end

      context "when subscription is created after billing_at" do
        let(:created_at) { billing_at + 1.day }

        it "does not enqueue a job on billing day" do
          billing_service.call

          expect(BillSubscriptionJob).not_to have_been_enqueued
            .with([subscription], billing_at.to_i, invoicing_reason: :subscription_periodic)
          expect(BillNonInvoiceableFeesJob).not_to have_been_enqueued
            .with([subscription], billing_at)
        end
      end
    end

    context "when billed quarterly with calendar billing time" do
      let(:interval) { :quarterly }
      let(:billing_time) { :calendar }
      let(:current_date) { DateTime.parse("01 Apr 2022") }

      it "enqueues a job on billing day" do
        billing_service.call

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        expect(BillNonInvoiceableFeesJob).to have_been_enqueued
          .with([subscription], current_date)
      end

      it "does not enqueue a job on other day" do
        current_date = DateTime.parse("01 May 2022")

        billing_service.call

        expect(BillSubscriptionJob).not_to have_been_enqueued
          .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        expect(BillNonInvoiceableFeesJob).not_to have_been_enqueued
          .with([subscription], current_date)
      end
    end

    context "when billed semiannual with calendar billing time" do
      let(:interval) { :semiannual }
      let(:billing_time) { :calendar }
      let(:current_date) { DateTime.parse("01 Jul 2022") }

      it "enqueues a job on billing day" do
        billing_service.call

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        expect(BillNonInvoiceableFeesJob).to have_been_enqueued
          .with([subscription], current_date)
      end

      it "does not enqueue a job on other day" do
        current_date = DateTime.parse("01 Aug 2022")

        billing_service.call

        expect(BillSubscriptionJob).not_to have_been_enqueued
          .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        expect(BillNonInvoiceableFeesJob).not_to have_been_enqueued
          .with([subscription], current_date)
      end

      context "when charges are billed monthly" do
        let(:bill_charges_monthly) { true }
        let(:current_date) { DateTime.parse("01 Aug 2022") }

        it "enqueues a job on billing day" do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          expect(BillNonInvoiceableFeesJob).to have_been_enqueued
            .with([subscription], current_date)
        end
      end
    end

    context "when billed yearly with calendar billing time" do
      let(:interval) { :yearly }
      let(:billing_time) { :calendar }

      let(:current_date) { DateTime.parse("01 Jan 2022") }

      it "enqueues a job on billing day" do
        billing_service.call

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        expect(BillNonInvoiceableFeesJob).to have_been_enqueued
          .with([subscription], current_date)
      end

      context "when billing at is not the billing day" do
        let(:billing_at) { DateTime.parse("02 Jan 2022") }

        it "does not enqueue a job on other day" do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context "when charges are billed monthly" do
        let(:bill_charges_monthly) { true }
        let(:billing_at) { DateTime.parse("01 Feb 2022") }

        it "enqueues a job on billing day" do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], billing_at.to_i, invoicing_reason: :subscription_periodic)
          expect(BillNonInvoiceableFeesJob).to have_been_enqueued
            .with([subscription], billing_at)
        end
      end
    end

    context "when billed weekly with anniversary billing time" do
      let(:interval) { :weekly }
      let(:billing_time) { :anniversary }

      let(:current_date) do
        DateTime.parse("20 Jun 2022").prev_occurring(subscription_at.strftime("%A").downcase.to_sym)
      end

      it "enqueues a job on billing day" do
        billing_service.call

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        expect(BillNonInvoiceableFeesJob).to have_been_enqueued
          .with([subscription], current_date)
      end

      context "when billing_at is a different day" do
        let(:billing_at) { current_date + 1.day }

        it "does not enqueue a job on other day" do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end
    end

    context "when billed monthly with anniversary billing time" do
      let(:interval) { :monthly }
      let(:billing_time) { :anniversary }
      let(:current_date) { subscription_at.next_month }

      it "enqueues a job on billing day" do
        billing_service.call

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        expect(BillNonInvoiceableFeesJob).to have_been_enqueued
          .with([subscription], current_date)
      end

      context "when billing_at is a different day" do
        let(:billing_at) { current_date + 1.day }

        it "does not enqueue a job on other day" do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context "when subscription anniversary is on a 31st" do
        let(:subscription_at) { DateTime.parse("31 Mar 2021") }
        let(:current_date) { DateTime.parse("28 Feb 2022") }

        it "enqueues a job if the month count less than 31 days" do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          expect(BillNonInvoiceableFeesJob).to have_been_enqueued
            .with([subscription], current_date)
        end
      end
    end

    context "when billed quarterly with anniversary billing time" do
      let(:interval) { :quarterly }
      let(:billing_time) { :anniversary }
      let(:current_date) { subscription_at + 3.months }

      it "enqueues a job on billing day" do
        billing_service.call

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        expect(BillNonInvoiceableFeesJob).to have_been_enqueued
          .with([subscription], current_date)
      end

      context "when billing_at is a different day" do
        let(:billing_at) { current_date + 1.day }

        it "does not enqueue a job on other day" do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context "when subscription anniversary is in March" do
        let(:subscription_at) { DateTime.parse("15 Mar 2021") }
        let(:current_date) { DateTime.parse("15 Sep 2022") }

        it "enqueues a job" do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          expect(BillNonInvoiceableFeesJob).to have_been_enqueued
            .with([subscription], current_date)
        end
      end

      context "when subscription anniversary is on a 31st" do
        let(:subscription_at) { DateTime.parse("31 Mar 2021") }
        let(:current_date) { DateTime.parse("30 Jun 2022") }

        it "enqueues a job if the month count less than 31 days" do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          expect(BillNonInvoiceableFeesJob).to have_been_enqueued
            .with([subscription], current_date)
        end
      end
    end

    context "when billed semiannually with anniversary billing time" do
      let(:interval) { :semiannual }
      let(:billing_time) { :anniversary }
      let(:current_date) { subscription_at + 6.months }

      it "enqueues a job on billing day" do
        billing_service.call

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        expect(BillNonInvoiceableFeesJob).to have_been_enqueued
          .with([subscription], current_date)
      end

      context "when billing_at is a different day" do
        let(:billing_at) { current_date + 1.day }

        it "does not enqueue a job on other day" do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context "when subscription anniversary is in March" do
        let(:subscription_at) { DateTime.parse("15 Mar 2021") }
        let(:current_date) { DateTime.parse("15 Sep 2022") }

        it "enqueues a job" do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          expect(BillNonInvoiceableFeesJob).to have_been_enqueued
            .with([subscription], current_date)
        end
      end

      context "when subscription anniversary is on a 31st" do
        let(:subscription_at) { DateTime.parse("31 Mar 2021") }
        let(:current_date) { DateTime.parse("30 Sep 2022") }

        it "enqueues a job if the month count less than 31 days" do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          expect(BillNonInvoiceableFeesJob).to have_been_enqueued
            .with([subscription], current_date)
        end
      end

      context "when charges are billed monthly" do
        let(:bill_charges_monthly) { true }
        let(:current_date) { subscription_at.next_month }

        context "when billing_at is the next month" do
          let(:billing_at) { current_date.next_month }

          it "enqueues a job on billing day" do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], billing_at.to_i, invoicing_reason: :subscription_periodic)
            expect(BillNonInvoiceableFeesJob).to have_been_enqueued
              .with([subscription], billing_at)
          end
        end

        context "when subscription anniversary is on a 31st" do
          let(:subscription_at) { DateTime.parse("31 Mar 2021") }
          let(:current_date) { DateTime.parse("28 Feb 2022") }

          it "enqueues a job if the month count less than 31 days" do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
            expect(BillNonInvoiceableFeesJob).to have_been_enqueued
              .with([subscription], current_date)
          end
        end
      end
    end

    context "when billed yearly with anniversary billing time" do
      let(:interval) { :yearly }
      let(:billing_time) { :anniversary }

      let(:current_date) { subscription_at.next_year }

      it "enqueues a job on billing day" do
        billing_service.call

        expect(BillSubscriptionJob).to have_been_enqueued
          .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        expect(BillNonInvoiceableFeesJob).to have_been_enqueued
          .with([subscription], current_date)
      end

      context "when billing_at is a different day" do
        let(:billing_at) { current_date + 1.day }

        it "does not enqueue a job on other day" do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context "when subscription anniversary is on 29th of february" do
        let(:subscription_at) { DateTime.parse("29 Feb 2020") }
        let(:current_date) { DateTime.parse("28 Feb 2022") }

        it "enqueues a job on 28th of february when year is not a leap year" do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          expect(BillNonInvoiceableFeesJob).to have_been_enqueued
            .with([subscription], current_date)
        end
      end

      context "when charges are billed monthly" do
        let(:bill_charges_monthly) { true }
        let(:current_date) { subscription_at.next_month }

        context "when billing_at is the next month" do
          let(:billing_at) { current_date.next_month }

          it "enqueues a job on billing day" do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], billing_at.to_i, invoicing_reason: :subscription_periodic)
            expect(BillNonInvoiceableFeesJob).to have_been_enqueued
              .with([subscription], billing_at)
          end
        end

        context "when subscription anniversary is on a 31st" do
          let(:subscription_at) { DateTime.parse("31 Mar 2021") }
          let(:current_date) { DateTime.parse("28 Feb 2022") }

          it "enqueues a job if the month count less than 31 days" do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
            expect(BillNonInvoiceableFeesJob).to have_been_enqueued
              .with([subscription], current_date)
          end
        end
      end
    end

    context "when downgraded" do
      let(:customer) { create(:customer, :with_hubspot_integration, organization:) }
      let(:current_date) { DateTime.parse("20 Feb 2022") }
      let(:subscription) do
        create(
          :subscription,
          customer:,
          subscription_at:,
          started_at: current_date - 10.days,
          previous_subscription:,
          status: :pending,
          created_at:
        )
      end

      let(:previous_subscription) do
        create(
          :subscription,
          customer:,
          subscription_at:,
          started_at: current_date - 10.days,
          billing_time: :anniversary,
          created_at:
        )
      end

      before { subscription }

      it "enqueues a job on billing day" do
        billing_service.call

        expect(Subscriptions::TerminateJob).to have_been_enqueued
          .with(previous_subscription, current_date.to_i)
      end
    end

    context "when on subscription creation day" do
      let(:subscription) do
        create(
          :subscription,
          customer:,
          plan:,
          subscription_at:,
          started_at:,
          billing_time:,
          created_at: subscription_at
        )
      end

      let(:interval) { :monthly }
      let(:billing_time) { :anniversary }
      let(:subscription_at) { DateTime.parse("2022-12-13T12:00:00Z") }
      let(:started_at) { subscription_at }
      let(:customer) { create(:customer, organization: plan.organization, timezone:) }
      let(:timezone) { nil }

      let(:billing_at) { subscription_at }

      it "does not enqueue a job" do
        expect { billing_service.call }.not_to have_enqueued_job
      end

      context "with customer timezone" do
        let(:timezone) { "Pacific/Noumea" }
        let(:billing_at) { subscription_at + 10.hours }

        it "does not enqueue a job" do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end
    end

    context "when subscription was already automatically billed today" do
      let(:interval) { :monthly }
      let(:billing_time) { :anniversary }
      let(:billing_at) { DateTime.parse("20 Jul 2021T12:00:00") }

      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          subscription:,
          invoicing_reason: :subscription_periodic,
          timestamp: billing_at - 1.hour,
          recurring: true
        )
      end

      before { invoice_subscription }

      it "does not enqueue a job" do
        expect { billing_service.call }.not_to have_enqueued_job
      end

      context "with customer timezone" do
        let(:timezone) { "Pacific/Noumea" }
        let(:billing_at) { DateTime.parse("20 Jul 2021T22:00:00") }

        it "does not enqueue a job" do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end
    end
  end
end
