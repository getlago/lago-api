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
  end
end
