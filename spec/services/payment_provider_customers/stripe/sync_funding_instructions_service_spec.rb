# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::Stripe::SyncFundingInstructionsService do
  subject(:update_service) { described_class.new(stripe_customer) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "USD") }
  let(:provider_customer_id) { "cus_Rw5Qso78STEap3" }
  let(:stripe_customer) { create(:stripe_customer, customer:, provider_payment_methods:) }
  let(:provider_payment_methods) { %w[customer_balance] }

  describe "#call" do
    context "when customer is not eligible" do
      let(:provider_payment_methods) { %w[card] }

      it "returns a successful result without doing anything" do
        expect(::Stripe::Customer).not_to receive(:create_funding_instructions)
        result = update_service.call
        expect(result).to be_success
      end
    end

    context "when customer is eligible and everything is valid and section does not yet exist" do
      let(:funding_instructions) do
        double("FundingInstructions", bank_transfer: double(to_hash: {some: "details"}))
      end

      let(:formatter_service_result) { double(details: "formatted bank details") }
      let(:invoice_custom_section) { create(:invoice_custom_section, organization:) }

      before do
        allow(stripe_customer.payment_provider).to receive(:secret_key).and_return("sk_test_123")
        allow(::Stripe::Customer).to receive(:create_funding_instructions)
          .and_return(funding_instructions)
        allow(InvoiceCustomSections::FundingInstructionsFormatterService).to receive(:call)
           .and_return(formatter_service_result)
        allow(InvoiceCustomSections::CreateService).to receive(:call)
           .and_return(double(invoice_custom_section: invoice_custom_section))
        allow(Customers::ManageInvoiceCustomSectionsService).to receive(:call)
      end

      it "creates the section and returns success" do
        result = update_service.call

        expect(result).to be_success
        expect(::Stripe::Customer).to have_received(:create_funding_instructions)
        expect(InvoiceCustomSections::FundingInstructionsFormatterService).to have_received(:call)
        expect(InvoiceCustomSections::CreateService).to have_received(:call)
        expect(Customers::ManageInvoiceCustomSectionsService).to have_received(:call)
      end
    end
  end
end
