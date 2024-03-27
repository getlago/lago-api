# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::UpdateInvoicePaymentDueDateService, type: :service do
  subject(:update_service) { described_class.new(customer:, net_payment_term:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:net_payment_term) { 30 }

  describe "#call" do
    let(:draft_invoice) do
      create(:invoice, status: :draft, customer:, issuing_date: DateTime.parse("21 Jun 2022"), organization:)
    end

    before do
      draft_invoice
    end

    it "updates invoice payment_due_date" do
      expect { update_service.call }.to change { draft_invoice.reload.payment_due_date }
        .from(DateTime.parse("21 Jun 2022"))
        .to(DateTime.parse("21 Jun 2022") + net_payment_term.days)
    end
  end
end
