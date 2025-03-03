# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CreateAdvanceChargesInvoiceSubscriptionService, type: :service do
  subject(:create_service) { described_class.new(invoice:, timestamp:, billing_periods:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }

  let(:invoice) { create(:invoice, organization:, customer:, status: :generating) }
  let(:timestamp) { Time.zone.parse("2025-03-01T00:00:01") }
  let(:billing_periods) do
    subscriptions.map do |s|
      {
        subscription_id: s.id,
        from_datetime: "2025-02-01T00:00:00",
        to_datetime: "2025-02-28T23:59:59",
        charges_from_datetime: "2025-02-01T00:00:00",
        charges_to_datetime: "2025-02-28T23:59:59"
      }
    end
  end

  let(:subscriptions) { create_list(:subscription, 3, customer:, plan:) }

  describe "#call" do
    it "create invoice subscriptions" do
      result = create_service.call

      expect(result).to be_success
      expect(result.invoice_subscriptions.count).to eq(3)

      invoice_subscription = result.invoice_subscriptions.first
      expect(invoice_subscription).to have_attributes(
        invoice:,
        subscription: subscriptions.first,
        timestamp:,
        from_datetime: match_datetime("2025-02-01T00:00:00"),
        to_datetime: match_datetime("2025-02-28T23:59:59"),
        charges_from_datetime: match_datetime("2025-02-01T00:00:00"),
        charges_to_datetime: match_datetime("2025-02-28T23:59:59"),
        recurring: false,
        invoicing_reason: "in_advance_charge_periodic"
      )
    end
  end
end
