# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CreateAdvanceChargesInvoiceSubscriptionService do
  subject(:create_service) do
    described_class.new(
      invoice:,
      timestamp:,
      subscriptions_with_fees: [latest_terminated_subscription],
      all_subscriptions: [latest_terminated_subscription, later_started_subscription]
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: :monthly, pay_in_advance: true) }
  let(:invoice) { create(:invoice, organization:, customer:, status: :generating) }
  let(:timestamp) { Time.zone.parse("2024-04-20T10:00:00") }

  let(:latest_terminated_subscription) do
    create(
      :subscription,
      :terminated,
      customer:,
      plan:,
      subscription_at: Date.new(2024, 1, 1),
      started_at: Time.zone.parse("2024-01-01T10:00:00"),
      terminated_at: timestamp
    )
  end

  let(:later_started_subscription) do
    create(
      :subscription,
      :terminated,
      customer:,
      plan:,
      subscription_at: Date.new(2024, 3, 15),
      started_at: Time.zone.parse("2024-03-15T10:00:00"),
      terminated_at: Time.zone.parse("2024-04-05T10:00:00")
    )
  end

  describe "#call" do
    it "uses the latest termination to drive boundaries when every subscription is terminated" do
      result = create_service.call

      expect(result).to be_success
      expect(invoice.invoice_subscriptions.sole).to have_attributes(
        charges_from_datetime: match_datetime("2024-04-01T00:00:00Z"),
        charges_to_datetime: match_datetime(timestamp)
      )
    end
  end
end
