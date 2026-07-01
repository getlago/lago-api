# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CreateAllPayInAdvanceFixedChargesJob do
  subject(:perform_now) { described_class.perform_now(plan, timestamp, fixed_charge) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:timestamp) { Time.current.to_i }
  let(:fixed_charge) { nil }

  describe "unique job behavior" do
    around do |example|
      ActiveJob::Uniqueness.reset_manager!
      example.run
      ActiveJob::Uniqueness.test_mode!
    end

    it "does not enqueue duplicate jobs" do
      expect do
        described_class.perform_later(plan, timestamp)
        described_class.perform_later(plan, timestamp)
      end.to change { enqueued_jobs.count }.by(1) # rubocop:disable RSpec/ExpectChange
    end
  end

  describe "#perform" do
    let(:subscription) { create(:subscription, :active, plan:) }
    let(:pending_subscription) { create(:subscription, :pending, plan:) }

    before do
      subscription
      pending_subscription
    end

    it "enqueues a job for each active subscription of the plan" do
      perform_now

      expect(Invoices::CreatePayInAdvanceFixedChargesJob)
        .to have_been_enqueued
        .with(subscription, timestamp)
      expect(Invoices::CreatePayInAdvanceFixedChargesJob)
        .not_to have_been_enqueued
        .with(pending_subscription, timestamp)
    end

    context "with a fixed charge" do
      let(:fixed_charge) { create(:fixed_charge, plan:, pay_in_advance: true) }
      let(:other_subscription) { create(:subscription, :active, plan:) }

      before do
        other_subscription
        create(:subscription_fixed_charge_units_override, subscription:, fixed_charge:, organization:)
      end

      it "skips subscriptions with a units override for the fixed charge" do
        perform_now

        expect(Invoices::CreatePayInAdvanceFixedChargesJob)
          .not_to have_been_enqueued
          .with(subscription, timestamp)
        expect(Invoices::CreatePayInAdvanceFixedChargesJob)
          .to have_been_enqueued
          .with(other_subscription, timestamp)
      end
    end
  end
end
