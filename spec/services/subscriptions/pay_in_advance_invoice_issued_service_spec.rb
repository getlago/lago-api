# frozen_string_literal: true

require "rails_helper"

describe Subscriptions::PayInAdvanceInvoiceIssuedService do
  subject(:result) { described_class.call(subscription:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: "monthly", pay_in_advance: true, amount_cents: 1000) }
  let(:subscription) do
    create(:subscription, organization:, customer:, plan:, status: :active, billing_time: :calendar,
      started_at: DateTime.new(2024, 1, 1), subscription_at: DateTime.new(2024, 1, 1))
  end
  let(:timestamp) { DateTime.new(2024, 2, 15) }

  let(:period_dates) do
    Subscriptions::DatesService.new_instance(subscription, DateTime.new(2024, 2, 1), current_usage: false)
  end

  context "when an invoice matches the period boundaries exactly" do
    before do
      create(:invoice_subscription,
        subscription:,
        invoice: create(:invoice, customer:, organization:, status: :finalized),
        recurring: true,
        from_datetime: period_dates.from_datetime,
        to_datetime: period_dates.to_datetime)
    end

    it "is issued" do
      expect(result.issued).to be(true)
    end
  end

  context "when an invoice only contains the timestamp but its boundaries differ" do
    before do
      create(:invoice_subscription,
        subscription:,
        invoice: create(:invoice, customer:, organization:, status: :finalized),
        recurring: true,
        from_datetime: period_dates.from_datetime - 1.day,
        to_datetime: period_dates.to_datetime + 1.day)
    end

    it "is not issued" do
      expect(result.issued).to be(false)
    end
  end

  context "when no invoice exists for the period" do
    it "is not issued" do
      expect(result.issued).to be(false)
    end
  end

  context "when it is the first period" do
    let(:subscription) do
      create(:subscription, organization:, customer:, plan:, status: :active, billing_time: :calendar,
        started_at: DateTime.new(2024, 1, 10), subscription_at: DateTime.new(2024, 1, 10))
    end
    let(:timestamp) { DateTime.new(2024, 1, 20) }

    it "is issued without requiring a matching invoice" do
      expect(result.issued).to be(true)
    end
  end
end
