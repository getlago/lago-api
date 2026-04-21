# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::ViesCheckJob do
  let(:customer) { create(:customer, tax_identification_number: "IE6388047V") }
  let(:vies_response) do
    {
      country_code: "FR"
    }
  end

  before do
    customer.billing_entity.update(eu_tax_management: true, country: "FR")

    allow(Customers::ApplyTaxesService).to receive(:call)
      .and_call_original
    allow_any_instance_of(Valvat).to receive(:exists?).and_return(vies_response) # rubocop:disable RSpec/AnyInstance
  end

  it "calls the ViesCheckService" do
    allow(Customers::ViesCheckService).to receive(:call).and_call_original

    described_class.perform_now(customer)

    expect(Customers::ViesCheckService).to have_received(:call).with(customer:)
  end

  context "when ViesCheckService returns a tax code" do
    it "applies the tax code" do
      described_class.perform_now(customer)

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
        expect { described_class.perform_now(customer) }
          .to have_enqueued_job(Invoices::FinalizePendingViesInvoiceJob).with(pending_invoice)
      end

      it "does not enqueue job for finalized invoices" do
        expect { described_class.perform_now(customer) }
          .not_to have_enqueued_job(Invoices::FinalizePendingViesInvoiceJob).with(finalized_invoice)
      end

      it "does not enqueue job for pending invoices with succeeded tax_status" do
        expect { described_class.perform_now(customer) }
          .not_to have_enqueued_job(Invoices::FinalizePendingViesInvoiceJob).with(pending_but_tax_succeeded_invoice)
      end

      context "when customer has gated invoices blocked by VIES" do
        let(:subscription) do
          create(:subscription, :incomplete, :with_activation_rules,
            activation_rules_config: [{type: "payment", timeout_hours: 48, status: "pending"}],
            customer:, organization: customer.organization)
        end
        let(:gated_invoice) do
          create(:invoice, :with_subscriptions, customer:, organization: customer.organization,
            status: :open, tax_status: "pending", subscriptions: [subscription])
        end

        before { gated_invoice }

        it "enqueues FinalizePendingViesInvoiceJob for gated invoices with pending tax_status" do
          expect { described_class.perform_now(customer) }
            .to have_enqueued_job(Invoices::FinalizePendingViesInvoiceJob).with(gated_invoice)
        end
      end
    end
  end

  context "when valvat has an error" do
    let(:pending_invoice) do
      create(:invoice, :pending, customer:, organization: customer.organization, tax_status: "pending")
    end

    before do
      pending_invoice
      allow_any_instance_of(Valvat).to receive(:exists?).and_raise(Valvat::Timeout.new("Timeout", "dummy")) # rubocop:disable RSpec/AnyInstance
    end

    it "enqueues another retry job" do
      expect { described_class.perform_now(customer) }.to have_enqueued_job(described_class)
    end

    it "does not apply taxes" do
      described_class.perform_now(customer)

      expect(Customers::ApplyTaxesService).not_to have_received(:call)
    end

    it "does not enqueue invoice finalization" do
      expect { described_class.perform_now(customer) }
        .not_to have_enqueued_job(Invoices::FinalizePendingViesInvoiceJob)
    end
  end
end
