# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RetryViesCheckJob do
  let(:customer) { create(:customer, tax_identification_number: "IE6388047V") }
  let(:vies_response) do
    {
      country_code: "FR"
    }
  end

  before do
    customer.billing_entity.update(eu_tax_management: true, country: "FR")

    allow(Customers::EuAutoTaxesService).to receive(:call)
      .with(customer: customer, new_record: false, tax_attributes_changed: true)
      .and_call_original
    allow(Customers::ApplyTaxesService).to receive(:call)
      .and_call_original
    allow_any_instance_of(Valvat).to receive(:exists?).and_return(vies_response) # rubocop:disable RSpec/AnyInstance
  end

  it "calls the EuAutoTaxesService" do
    described_class.perform_now(customer.id)

    expect(Customers::EuAutoTaxesService).to have_received(:call)
  end

  context "when customer has no tax identification number" do
    let(:customer) { create(:customer, tax_identification_number: nil) }

    it "returns early" do
      described_class.perform_now(customer.id)

      expect(Customers::EuAutoTaxesService).not_to have_received(:call)
    end
  end

  context "when EuAutoTaxesService returns a tax code" do
    it "applies the tax code" do
      described_class.perform_now(customer.id)

      expect(Customers::ApplyTaxesService).to have_received(:call)
        .with(customer: customer, tax_codes: ["lago_eu_fr_standard"])
    end

    context "when customer has pending invoices blocked by VIES" do
      let(:pending_invoice) do
        create(:invoice, :pending, customer:, organization: customer.organization, tax_status: "pending")
      end
      let(:finalized_invoice) do
        create(:invoice, :finalized, customer:, organization: customer.organization)
      end
      let(:pending_but_tax_succeeded_invoice) do
        create(:invoice, :pending, customer:, organization: customer.organization, tax_status: "succeeded")
      end

      before do
        pending_invoice
        finalized_invoice
        pending_but_tax_succeeded_invoice
      end

      it "enqueues FinalizePendingViesInvoiceJob for pending invoices with pending tax_status" do
        expect { described_class.perform_now(customer.id) }
          .to have_enqueued_job(Invoices::FinalizePendingViesInvoiceJob).with(pending_invoice)
      end

      it "does not enqueue job for finalized invoices" do
        expect { described_class.perform_now(customer.id) }
          .not_to have_enqueued_job(Invoices::FinalizePendingViesInvoiceJob).with(finalized_invoice)
      end

      it "does not enqueue job for pending invoices with succeeded tax_status" do
        expect { described_class.perform_now(customer.id) }
          .not_to have_enqueued_job(Invoices::FinalizePendingViesInvoiceJob).with(pending_but_tax_succeeded_invoice)
      end
    end
  end

  context "when valvat has an error" do
    before do
      allow_any_instance_of(Valvat).to receive(:exists?).and_raise(Valvat::Timeout.new("Timeout", "dummy")) # rubocop:disable RSpec/AnyInstance
    end

    it "applies the taxes and enqueues another job" do
      expect { described_class.perform_now(customer.id) }.to have_enqueued_job(described_class)
    end
  end
end
