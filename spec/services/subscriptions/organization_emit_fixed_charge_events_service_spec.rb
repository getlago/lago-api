# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::OrganizationEmitFixedChargeEventsService, type: :service do
  include ActiveJob::TestHelper

  subject(:service) { described_class.new(organization:, timestamp:) }

  shared_examples "enqueues jobs for each customer" do
    it "enqueues a Subscriptions::EmitFixedChargeEventsJob for each customer" do
      travel_to(timestamp) do
        expect { service.call }.to have_enqueued_job(Subscriptions::EmitFixedChargeEventsJob).exactly(2)

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
        expect { service.call }.not_to have_enqueued_job(Subscriptions::EmitFixedChargeEventsJob)
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

      context "when fixed charges are billed monthly" do
        let(:bill_fixed_charges_monthly) { true }
        let(:subscription_at) { timestamp - 2.months }

        include_examples "enqueues jobs for each customer"
      end

      context "when not a year after the subscription anniversary" do
        let(:subscription_at) { timestamp - 11.months }

        include_examples "does not enqueue any jobs"
      end
    end
  end
end
