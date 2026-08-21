# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::Subscriptions::BillService do
  describe ".call" do
    subject(:result) { described_class.call(subscriptions:, start_on:, end_on:) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:, pricing_type: "product_catalog") }
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }
    let(:subscriptions) { [subscription] }
    let(:start_on) { "2026-08-01" }
    let(:end_on) { "2026-08-14" }
    let(:billing_result) do
      BillingCycles::BillSubscriptionService::Result.new.tap do |result|
        result.invoices = []
      end
    end

    before do
      allow(BillingCycles::BillSubscriptionService).to receive(:call).and_return(billing_result)
    end

    it "converts date boundaries to timestamps before billing" do
      result

      expect(BillingCycles::BillSubscriptionService).to have_received(:call).with(
        subscription:,
        range: Time.zone.parse("2026-08-01")..Time.zone.parse("2026-08-14").end_of_day
      )
    end

    context "with an invalid range" do
      let(:start_on) { "2026-08-14" }
      let(:end_on) { "2026-08-01" }

      it "returns a validation error" do
        result

        expect(result.error.messages).to eq(range: ["invalid_date_range"])
        expect(BillingCycles::BillSubscriptionService).not_to have_received(:call)
      end
    end

    context "with a quoted date range" do
      let(:start_on) { nil }
      let(:end_on) { '"2026-09-10"' }

      it "removes extra quotes before billing" do
        result

        expect(BillingCycles::BillSubscriptionService).to have_received(:call).with(
          subscription:,
          range: Time.zone.parse("2026-09-09")..Time.zone.parse("2026-09-10").end_of_day
        )
      end
    end

    context "with an invalid date" do
      let(:start_on) { nil }
      let(:end_on) { "hello" }

      it "returns a validation error" do
        result

        expect(result.error.messages).to eq(range: ["invalid_date_range"])
        expect(BillingCycles::BillSubscriptionService).not_to have_received(:call)
      end
    end
  end
end
