# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RefreshInvoicesSearchTermsService do
  subject(:refresh_service) { described_class.new(customer:) }

  describe "#call" do
    context "when the customer is nil" do
      let(:customer) { nil }

      it "returns a not found failure" do
        expect(refresh_service.call.error).to be_a(BaseService::NotFoundFailure)
      end
    end

    context "with a customer" do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:customer) { create(:customer, organization:, name: "Acme Inc") }
      let_it_be(:other_customer) { create(:customer, organization:, name: "Globex") }

      let_it_be(:invoice) { create(:invoice, organization:, customer:, number: "INV-001") }
      let_it_be(:other_invoice) { create(:invoice, organization:, customer: other_customer, number: "INV-002") }

      before do
        Invoice.where(id: [invoice.id, other_invoice.id]).update_all(search_terms: nil) # rubocop:disable Rails/SkipsModelValidations
      end

      it "refreshes every invoice of the customer" do
        refresh_service.call

        expect(invoice.reload.search_terms).to include("INV-001", "Acme Inc")
      end

      it "leaves other customers' invoices untouched" do
        refresh_service.call

        expect(other_invoice.reload.search_terms).to be_nil
      end

      it "returns the customer" do
        expect(refresh_service.call.customer).to eq(customer)
      end

      context "with more invoices than one batch" do
        before do
          stub_const("#{described_class}::BATCH_SIZE", 1)
          create(:invoice, organization:, customer:, number: "INV-003")
        end

        it "refreshes them all" do
          refresh_service.call

          expect(customer.invoices.pluck(:search_terms)).to all(include("Acme Inc"))
        end
      end

      context "when the customer name changed" do
        before do
          refresh_service.call
          customer.update!(name: "Acme Renamed")
        end

        it "rewrites the invoices with the new name" do
          described_class.new(customer:).call

          expect(invoice.reload.search_terms).to include("Acme Renamed")
        end
      end
    end
  end
end
