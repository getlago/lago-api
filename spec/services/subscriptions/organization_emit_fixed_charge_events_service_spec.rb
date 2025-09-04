# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::OrganizationEmitFixedChargeEventsService, type: :service do
  include ActiveJob::TestHelper

  subject(:service) { described_class.new(organization:, timestamp:) }

  shared_examples "enqueues jobs for each customer" do
    it "enqueues a Subscriptions::EmitFixedChargeEventsJob for each customer" do
      travel_to(timestamp) do
        expect(service.call).to be_a_success

        expect(Subscriptions::EmitFixedChargeEventsJob).to have_been_enqueued.exactly(2).times

        expect(Subscriptions::EmitFixedChargeEventsJob)
          .to have_been_enqueued
          .with(
            subscriptions: contain_exactly(subscription_1, subscription_2),
            timestamp: timestamp.to_i
          )

        expect(Subscriptions::EmitFixedChargeEventsJob)
          .to have_been_enqueued
          .with(
            subscriptions: contain_exactly(subscription_3),
            timestamp: timestamp.to_i
          )
      end
    end
  end

  shared_examples "does not enqueue any jobs" do
    it "does not enqueue any jobs" do
      travel_to(timestamp) do
        expect(service.call).to be_a_success

        expect(Subscriptions::EmitFixedChargeEventsJob).not_to have_been_enqueued
      end
    end
  end

  let(:timestamp) { Time.current }
  let(:organization) { create(:organization) }

  describe "#call" do
    let(:plan) { create(:plan, organization:, interval:, bill_fixed_charges_monthly:) }
    let(:bill_fixed_charges_monthly) { false }
    let(:fixed_charge) { create(:fixed_charge, plan:, add_on:) }
    let(:customer_1) { create(:customer, organization:) }
    let(:customer_2) { create(:customer, organization:) }
    let(:add_on) { create(:add_on, organization:) }
    let(:subscription_1) do
      create(
        :subscription,
        billing_time:,
        plan:,
        customer: customer_1,
        subscription_at:,
        started_at: subscription_at,
        created_at: subscription_created_at
      )
    end
    let(:subscription_2) do
      create(
        :subscription,
        billing_time:,
        plan:,
        customer: customer_1,
        subscription_at:,
        started_at: subscription_at,
        created_at: subscription_created_at
      )
    end
    let(:subscription_3) do
      create(
        :subscription,
        billing_time:,
        plan:,
        customer: customer_2,
        subscription_at:,
        started_at: subscription_at,
        created_at: subscription_created_at
      )
    end
    let(:subscription_at) { timestamp - 10.days }
    let(:subscription_created_at) { timestamp - 15.days }

    context "when billed weekly with calendar billing time" do
      let(:interval) { :weekly }
      let(:billing_time) { :calendar }
      let(:timestamp) { Time.zone.parse("2024-01-01") } # This is a Monday

      before do
        fixed_charge
        subscription_1
        subscription_2
        subscription_3
      end

      include_examples "enqueues jobs for each customer"

      context "when not on a Monday" do
        let(:timestamp) { Time.zone.parse("2024-01-02") } # Tuesday

        include_examples "does not enqueue any jobs"
      end
    end

    context "when billed monthly with calendar billing time" do
      let(:interval) { :monthly }
      let(:billing_time) { :calendar }
      let(:timestamp) { Time.zone.parse("2024-02-01") } # This is a 1st day of the month (not Monday)

      before do
        fixed_charge
        subscription_1
        subscription_2
        subscription_3
      end

      include_examples "enqueues jobs for each customer"

      context "when not on a 1st day of the month" do
        let(:timestamp) { Time.zone.parse("2024-02-02") } # 2nd day of the month

        include_examples "does not enqueue any jobs"
      end

      context "when subscription started after timestamp" do
        let(:subscription_at) { timestamp + 1.day }

        include_examples "does not enqueue any jobs"
      end

      context "when subscriptions are pending" do
        before do
          subscription_1.update!(status: :pending)
          subscription_2.update!(status: :pending)
          subscription_3.update!(status: :pending)
        end

        include_examples "does not enqueue any jobs"
      end

      context "when subscription already emitted on timestamp" do
        before do
          create(:fixed_charge_event, subscription: subscription_1, timestamp:)
          create(:fixed_charge_event, subscription: subscription_2, timestamp:)
          create(:fixed_charge_event, subscription: subscription_3, timestamp:)
        end

        include_examples "does not enqueue any jobs"
      end

      context "when ending_at is the same as billing day" do
        let(:subscription_4) do
          create(
            :subscription,
            plan:,
            subscription_at:,
            started_at: subscription_at,
            billing_time:,
            ending_at: timestamp,
            customer: customer_3
          )
        end
        let(:customer_3) { create(:customer, organization:) }

        before { subscription_4 }

        it "does not enqueue a job for the subscription" do
          travel_to(timestamp) do
            expect(service.call).to be_a_success

            expect(Subscriptions::EmitFixedChargeEventsJob)
              .not_to have_been_enqueued
              .with(
                subscriptions: contain_exactly(subscription_4),
                timestamp: timestamp.to_i
              )
          end
        end
      end

      context "when subscription is created after timestamp" do
        let(:subscription_4_created_at) { timestamp + 1.day }
        let(:subscription_4) do
          create(
            :subscription,
            plan:,
            subscription_at:,
            created_at: subscription_4_created_at,
            started_at: subscription_at,
            billing_time:,
            customer: customer_3
          )
        end
        let(:customer_3) { create(:customer, organization:) }

        before { subscription_4 }

        it "does not enqueue a job on billing day" do
          travel_to(timestamp) do
            expect(service.call).to be_a_success

            expect(Subscriptions::EmitFixedChargeEventsJob)
              .not_to have_been_enqueued
              .with(
                subscriptions: contain_exactly(subscription_4),
                timestamp: timestamp.to_i
              )
          end
        end
      end

      context "when plan fixed charges are discarded after timestamp" do
        before { fixed_charge.update!(deleted_at: timestamp + 1.day) }

        include_examples "enqueues jobs for each customer"
      end

      context "when plan fixed charges are discarded" do
        before { fixed_charge.update!(deleted_at: timestamp) }

        include_examples "does not enqueue any jobs"
      end

      context "when plan has no fixed charges" do
        before { fixed_charge.destroy! }

        include_examples "does not enqueue any jobs"
      end
    end

    context "when billed quarterly with calendar billing time" do
      let(:interval) { :quarterly }
      let(:billing_time) { :calendar }
      let(:timestamp) { Time.zone.parse("2024-10-01") } # 1st day of the quarter

      before do
        fixed_charge
        subscription_1
        subscription_2
        subscription_3
      end

      include_examples "enqueues jobs for each customer"

      context "when not on a 1st day of the quarter" do
        let(:timestamp) { Time.zone.parse("2024-11-01") } # not 1st day of the quarter

        include_examples "does not enqueue any jobs"
      end
    end

    context "when billed yearly with calendar billing time" do
      let(:interval) { :yearly }
      let(:billing_time) { :calendar }
      let(:timestamp) { Time.zone.parse("2024-01-01") } # 1st day of the year

      before do
        fixed_charge
        subscription_1
        subscription_2
        subscription_3
      end

      include_examples "enqueues jobs for each customer"

      context "when fixed charges are billed monthly" do
        let(:bill_fixed_charges_monthly) { true }
        let(:timestamp) { Time.zone.parse("2025-02-01") } # not 1st day of the year but 1st day of the month

        include_examples "enqueues jobs for each customer"
      end

      context "when not on a 1st day of the year" do
        let(:timestamp) { Time.zone.parse("2024-03-01") } # not 1st day of the year but 1st day of the month

        include_examples "does not enqueue any jobs"
      end
    end

    context "when billed weekly with anniversary billing time" do
      let(:interval) { :weekly }
      let(:billing_time) { :anniversary }
      let(:subscription_at) { timestamp - 7.days }

      before do
        fixed_charge
        subscription_1
        subscription_2
        subscription_3
      end

      include_examples "enqueues jobs for each customer"

      context "when not a week after the subscription anniversary" do
        let(:subscription_at) { timestamp - 2.days }

        include_examples "does not enqueue any jobs"
      end
    end

    context "when billed monthly with anniversary billing time" do
      let(:interval) { :monthly }
      let(:billing_time) { :anniversary }
      let(:subscription_at) { timestamp - 1.month }

      before do
        fixed_charge
        subscription_1
        subscription_2
        subscription_3
      end

      include_examples "enqueues jobs for each customer"

      context "when not a month after the subscription anniversary" do
        let(:subscription_at) { timestamp - 3.weeks }

        include_examples "does not enqueue any jobs"
      end

      context "when subscription anniversary is on a 31st and the month count less than 31 days" do
        let(:subscription_at) { DateTime.parse("31 Mar 2021") }
        let(:timestamp) { DateTime.parse("28 Feb 2022") }

        include_examples "enqueues jobs for each customer"
      end
    end

    context "when billed quarterly with anniversary billing time" do
      let(:interval) { :quarterly }
      let(:billing_time) { :anniversary }
      let(:subscription_at) { timestamp - 3.months }

      before do
        fixed_charge
        subscription_1
        subscription_2
        subscription_3
      end

      include_examples "enqueues jobs for each customer"

      context "when subscription anniversary is in March" do
        let(:subscription_at) { DateTime.parse("15 Mar 2021") }
        let(:timestamp) { DateTime.parse("15 Sep 2022") }

        include_examples "enqueues jobs for each customer"
      end

      context "when subscription anniversary is on a 31st and the month count less than 31 days" do
        let(:subscription_at) { DateTime.parse("31 Mar 2021") }
        let(:timestamp) { DateTime.parse("30 Jun 2022") }

        include_examples "enqueues jobs for each customer"
      end

      context "when not a quarter after the subscription anniversary" do
        let(:subscription_at) { timestamp - 2.months }

        include_examples "does not enqueue any jobs"
      end
    end

    context "when billed yearly with anniversary billing time" do
      let(:interval) { :yearly }
      let(:billing_time) { :anniversary }
      let(:subscription_at) { timestamp - 1.year }

      before do
        fixed_charge
        subscription_1
        subscription_2
        subscription_3
      end

      include_examples "enqueues jobs for each customer"

      context "when subscription anniversary is on 29th of february and the year is not a leap year" do
        let(:subscription_at) { DateTime.parse("29 Feb 2020") }
        let(:timestamp) { DateTime.parse("28 Feb 2021") }

        include_examples "enqueues jobs for each customer"
      end

      context "when fixed charges are billed monthly" do
        let(:bill_fixed_charges_monthly) { true }
        let(:subscription_at) { timestamp - 2.months }

        include_examples "enqueues jobs for each customer"

        context "when subscription anniversary is on a 31st and the month count less than 31 days" do
          let(:timestamp) { DateTime.parse("28 Feb 2022") }
          let(:subscription_at) { DateTime.parse("31 Jan 2022") }

          include_examples "enqueues jobs for each customer"
        end
      end

      context "when not a year after the subscription anniversary" do
        let(:subscription_at) { timestamp - 11.months }

        include_examples "does not enqueue any jobs"
      end
    end

    context "when on subscription creation day" do
      let(:subscription_created_at) { DateTime.parse("2022-12-13T12:00:00Z") }
      let(:subscription_at) { subscription_created_at }
      let(:timestamp) { subscription_created_at }
      let(:timezone) { nil }
      let(:interval) { :monthly }
      let(:billing_time) { :anniversary }

      let(:customer_1) { create(:customer, organization:, timezone:) }

      before do
        fixed_charge
        subscription_1
      end

      include_examples "does not enqueue any jobs"

      context "with customer timezone" do
        let(:timezone) { "Pacific/Noumea" }
        let(:timestamp) { subscription_created_at + 10.hours }

        include_examples "does not enqueue any jobs"
      end
    end

    context "when subscription is downgraded" do
      let(:interval) { :monthly }
      let(:customer) { create(:customer, organization:) }
      let(:timestamp) { DateTime.parse("1 Feb 2022") }
      let(:downgrade_plan) { create(:plan, organization:, interval:) }

      let(:subscription) do
        create(
          :subscription,
          :calendar,
          customer:,
          plan: downgrade_plan,
          status: :pending,
          subscription_at: previous_subscription_created_at,
          started_at: nil,
          previous_subscription:,
          created_at: timestamp - 10.days
        )
      end

      let(:previous_subscription_created_at) { timestamp - 3.months }
      let(:previous_subscription) do
        create(
          :subscription,
          :calendar,
          customer:,
          plan:,
          subscription_at: previous_subscription_created_at,
          started_at: previous_subscription_created_at,
          created_at: previous_subscription_created_at
        )
      end

      before do
        fixed_charge
        subscription
      end

      include_examples "does not enqueue any jobs"
    end
  end
end
