# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReceipt, type: :model do
  subject(:payment_receipt) { build(:payment_receipt) }

  it { is_expected.to belong_to(:payment) }
  it { is_expected.to belong_to(:organization) }

  describe ".for_organization" do
    subject(:result) { described_class.for_organization(organization) }

    let(:organization) { create(:organization) }
    let(:visible_invoice) { create(:invoice, organization:, status: Invoice::VISIBLE_STATUS[:finalized]) }
    let(:invisible_invoice) { create(:invoice, organization:, status: Invoice::INVISIBLE_STATUS[:generating]) }
    let(:payment_request) { create(:payment_request, organization:) }
    let(:other_org_payment_request) { create(:payment_request) }

    let(:visible_invoice_payment) { create(:payment, payable: visible_invoice) }
    let!(:visible_invoice_payment_receipt) { create(:payment_receipt, payment: visible_invoice_payment) }

    let(:invisible_invoice_payment) { create(:payment, payable: invisible_invoice) }
    let!(:invisible_invoice_payment_receipt) { create(:payment_receipt, payment: invisible_invoice_payment) }

    let(:payment_request_payment) { create(:payment, payable: payment_request) }
    let!(:payment_request_payment_receipt) { create(:payment_receipt, payment: payment_request_payment, organization:) }

    let(:other_org_invoice_payment) { create(:payment) }
    let!(:other_org_invoice_payment_receipt) do
      create(:payment_receipt, payment: other_org_invoice_payment, organization:)
    end

    let(:other_org_payment_request_payment) { create(:payment, payable: other_org_payment_request) }

    let(:other_org_payment_request_payment_receipt) do
      create(:payment_receipt, payment: other_org_payment_request_payment, organization:)
    end

    it "returns payments and payment requests for the organization's visible invoices" do
      payments = subject

      expect(payments).to include(visible_invoice_payment_receipt)
      expect(payments).to include(payment_request_payment_receipt)
      expect(payments).not_to include(invisible_invoice_payment_receipt)
      expect(payments).not_to include(other_org_invoice_payment_receipt)
      expect(payments).not_to include(other_org_payment_request_payment_receipt)
    end
  end
end
