# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RefreshSearchTermsService do
  subject(:refresh_service) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }

  let(:customer) do
    create(
      :customer,
      organization:,
      name: "Acme Inc",
      firstname: "Rick",
      lastname: "Sanchez",
      legal_name: "Acme Incorporated",
      external_id: "cust-1",
      email: "rick@acme.test"
    )
  end

  let(:invoice) do
    create(:invoice, organization:, customer:, number: "INV-001", purchase_order_number: "PO-42")
  end

  def search_terms
    invoice.reload.search_terms
  end

  describe "#call" do
    it "concatenates the invoice and customer fields" do
      refresh_service.call

      expect(search_terms).to eq("INV-001 PO-42 Acme Inc Rick Sanchez Acme Incorporated cust-1 rick@acme.test")
    end

    it "returns the invoice" do
      expect(refresh_service.call.invoice).to eq(invoice)
    end

    context "when a field is nil" do
      let(:invoice) do
        create(:invoice, organization:, customer:, number: "INV-001", purchase_order_number: nil)
      end

      it "skips it without leaving a double separator" do
        refresh_service.call

        expect(search_terms).to eq("INV-001 Acme Inc Rick Sanchez Acme Incorporated cust-1 rick@acme.test")
      end
    end

    context "when a field is an empty string" do
      before { customer.update!(firstname: "") }

      it "keeps the separator, as concat_ws does" do
        refresh_service.call

        expect(search_terms).to eq("INV-001 PO-42 Acme Inc  Sanchez Acme Incorporated cust-1 rick@acme.test")
      end
    end

    context "when the invoice has no customer" do
      before { invoice.update_column(:customer_id, nil) } # rubocop:disable Rails/SkipsModelValidations

      it "writes the invoice fields only" do
        refresh_service.call

        expect(search_terms).to eq("INV-001 PO-42")
      end
    end

    context "when the customer is discarded" do
      before { customer.discard! }

      it "keeps the customer fields" do
        refresh_service.call

        expect(search_terms).to include("Acme Inc")
      end
    end

    context "when called twice" do
      before { refresh_service.call }

      it "is idempotent" do
        expect { described_class.new(invoice:).call }.not_to change { search_terms }
      end
    end

    context "when the invoice is nil" do
      let(:invoice) { nil }

      it "returns a not found failure" do
        expect(refresh_service.call.error).to be_a(BaseService::NotFoundFailure)
      end
    end
  end
end
