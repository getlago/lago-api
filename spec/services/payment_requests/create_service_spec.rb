# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::CreateService, type: :service do
  subject(:create_service) { described_class.new(organization:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  let(:first_invoice) { create(:invoice, customer:) }
  let(:second_invoice) { create(:invoice, customer:) }
  let(:params) do
    {
      external_customer_id: customer.external_id,
      email: "john.doe@example.com",
      lago_invoice_ids: [first_invoice.id, second_invoice.id]
    }
  end

  describe "#call" do
    it "creates a payable group for the customer" do
      expect { create_service.call }.to change { customer.payable_groups.count }.by(1)
    end

    it "assigns the payable group to the invoices" do
      expect { create_service.call }
        .to change { first_invoice.reload.payable_group }.from(nil).to(be_a(PayableGroup))
        .and change { second_invoice.reload.payable_group }.from(nil).to(be_a(PayableGroup))
    end

    it "creates a payment request" do
      expect { create_service.call }.to change { customer.payment_requests.count }.by(1)
    end

    it "returns the payment request", :aggregate_failures do
      result = create_service.call

      expect(result.payment_request).to be_a(PaymentRequest)
      expect(result.payment_request).to have_attributes(
        organization:,
        customer:,
        amount_cents: first_invoice.total_amount_cents + second_invoice.total_amount_cents,
        amount_currency: "EUR",
        email: "john.doe@example.com"
      )
    end
  end
end
