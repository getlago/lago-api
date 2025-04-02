# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::UpdateInvoiceNumberingService, type: :service do
  subject(:update_service) { described_class.new(organization:, document_numbering:) }

  let(:organization) { create(:organization, document_numbering: "per_customer") }
  let(:document_numbering) { "per_organization" }

  describe "#call" do
    it "updates the organization's document_numbering" do
      result = update_service.call

      expect(result).to be_success
      expect(result.organization).to be_per_organization
    end

    context "when document_numbering is not changing" do
      let(:document_numbering) { "per_customer" }

      it "returns early without making changes" do
        result = update_service.call

        expect(result).to be_success
        expect(result.organization).to be_per_customer
      end
    end

    context "when changing from per_customer to per_organization" do
      let(:customer) { create(:customer, organization:) }
      let(:invoice1) { create(:invoice, customer:, organization:, status: "finalized", self_billed: false) }
      let(:invoice2) { create(:invoice, customer:, organization:, status: "finalized", self_billed: false) }
      let(:invoice3) { create(:invoice, customer:, organization:, status: "draft", self_billed: false) }
      let(:voided_invoice) { create(:invoice, customer:, organization:, status: "voided", self_billed: false) }
      let(:self_billed_invoice) { create(:invoice, customer:, organization:, status: "finalized", self_billed: true) }

      before do
        invoice1
        invoice2 
        invoice3
        self_billed_invoice
        voided_invoice
      end
      

      it "updates the organization sequential id for the latest invoice" do
        expect {
          update_service.call
        }.to change { voided_invoice.reload.organization_sequential_id }.to(3)

        expect(organization).to be_per_organization
      end

      it "only counts non-self-billed invoices with generated numbers" do
        result = update_service.call

        expect(result).to be_success
        expect(voided_invoice.reload.organization_sequential_id).to eq(3)
      end
    end

    context "when changing from per_organization to per_customer" do
      let(:organization) { create(:organization, document_numbering: "per_organization") }
      let(:document_numbering) { "per_customer" }

      it "updates the organization's document_numbering without other changes" do
        result = update_service.call

        expect(result).to be_success
        expect(result.organization).to be_per_customer
      end
    end
  end
end 