# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::RefreshDraftService do
  subject(:result) { described_class.call(invoice:, context:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "USD") }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, units: 5)
  end
  let(:rate_card_rate) do
    create(:rate_card_rate, organization:, rate_card:, rate_properties: {"amount" => "15.00"})
  end
  let(:invoice) do
    create(
      :invoice,
      :draft,
      organization:,
      customer:,
      billing_entity: customer.billing_entity,
      invoice_type: :subscription,
      currency: "USD",
      ready_to_be_refreshed: true
    )
  end
  let(:billing_segment) do
    create(
      :billing_segment,
      organization:,
      customer:,
      contract:,
      contract_rate_card:,
      rate_card_rate:,
      invoice:,
      status: :done,
      currency: "USD"
    )
  end
  let(:context) { :draft }

  before { billing_segment }

  it "rebuilds the product fees and totals from the billing segments" do
    expect(result).to be_success

    expect(invoice.reload).to have_attributes(
      status: "draft",
      ready_to_be_refreshed: false,
      fees_amount_cents: 7_500,
      total_amount_cents: 7_500
    )
    expect(invoice.fees.sole).to have_attributes(invoiceable: product, amount_cents: 7_500)
  end

  context "when finalizing" do
    let(:context) { :finalize }

    it "computes the final amounts without changing the invoice status" do
      expect(result).to be_success
      expect(invoice.reload).to have_attributes(status: "draft", total_amount_cents: 7_500)
    end
  end

  context "when the invoice finalization job runs" do
    subject(:finalization_result) { Invoices::RefreshDraftAndFinalizeService.call(invoice:) }

    it "refreshes the product fees before finalizing the invoice" do
      expect(finalization_result).to be_success
      expect(invoice.reload).to have_attributes(status: "finalized", total_amount_cents: 7_500)
      expect(invoice.fees.sole).to have_attributes(invoiceable: product, amount_cents: 7_500)
    end
  end

  context "when fee recomputation fails" do
    let(:original_fee) do
      create(
        :fee,
        invoice:,
        organization:,
        billing_entity: invoice.billing_entity,
        amount_cents: 1_000
      )
    end
    let(:compute_result) do
      BillingSegments::ComputeInvoiceService::Result.new.tap do |service_result|
        service_result.validation_failure!(errors: {base: ["invalid"]})
      end
    end

    before do
      original_fee
      invoice.update!(fees_amount_cents: 1_000, total_amount_cents: 1_000)
      allow(BillingSegments::ComputeInvoiceService).to receive(:call!).and_raise(compute_result.error)
    end

    it "returns its own failure result and rolls back the invoice reset" do
      expect(result).to be_a(described_class::Result)
      expect(result).to be_failure
      expect(invoice.reload).to have_attributes(
        ready_to_be_refreshed: true,
        fees_amount_cents: 1_000,
        total_amount_cents: 1_000
      )
      expect(original_fee.reload).not_to be_discarded
    end
  end
end
