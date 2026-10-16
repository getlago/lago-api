# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::InvoiceSerializer do
  subject(:serializer) { described_class.new(invoice, root_name: "invoice", includes:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:contract) { create(:contract, organization:, customer:) }
  let_it_be(:product) { create(:product, organization:) }

  let(:includes) { [] }
  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      invoice_type: :contract,
      number: "LAG-2025-001",
      purchase_order_number: "PO-42",
      fees_amount_cents: 1_000,
      coupons_amount_cents: 100,
      sub_total_excluding_taxes_amount_cents: 900,
      taxes_amount_cents: 180,
      sub_total_including_taxes_amount_cents: 1_080,
      total_amount_cents: 1_080,
      total_paid_amount_cents: 80
    )
  end
  let(:result) { JSON.parse(serializer.to_json)["invoice"] }

  it "serializes the compact payload" do
    expect(result).to eq(
      "lago_id" => invoice.id,
      "number" => "LAG-2025-001",
      "invoice_type" => "contract",
      "status" => "finalized",
      "payment_status" => "pending",
      "billing_entity_code" => invoice.billing_entity.code,
      "lago_customer_id" => customer.id,
      "external_customer_id" => customer.external_id,
      "currency" => "EUR",
      "issuing_date" => invoice.issuing_date.iso8601,
      "payment_due_date" => invoice.payment_due_date.iso8601,
      "payment_overdue" => false,
      "payment_dispute_lost_at" => nil,
      "purchase_order_number" => "PO-42",
      "fees_amount_cents" => 1_000,
      "coupons_amount_cents" => 100,
      "sub_total_excluding_taxes_amount_cents" => 900,
      "taxes_amount_cents" => 180,
      "sub_total_including_taxes_amount_cents" => 1_080,
      "credit_notes_amount_cents" => 0,
      "total_amount_cents" => 1_080,
      "total_offsetted_credit_note_amount_cents" => 0,
      "total_paid_amount_cents" => 80,
      "total_due_amount_cents" => 1_000,
      "file_url" => nil,
      "xml_url" => nil,
      "voided_at" => nil,
      "created_at" => invoice.created_at.iso8601,
      "updated_at" => invoice.updated_at.iso8601
    )
  end

  context "when the invoice bills fees in advance" do
    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :advance_charges) }

    it "names the type advance_fees" do
      expect(result["invoice_type"]).to eq("advance_fees")
    end
  end

  context "with the detail includes" do
    let(:includes) { described_class::DETAIL_INCLUDES }
    let(:tax) { create(:tax, organization:) }
    let(:other_contract) { create(:contract, organization:, customer:) }
    let(:fee_attributes) { {invoice:, subscription: nil, fee_type: :product, invoiceable: product, contract:} }
    let(:later_fee) { create(:fee, fee_attributes.merge(created_at: 1.hour.ago)) }
    let(:earlier_fee) { create(:fee, fee_attributes.merge(created_at: 2.hours.ago)) }
    let(:event_fee) do
      create(:fee, fee_attributes.merge(contract: other_contract, pay_in_advance: true, pay_in_advance_event_transaction_id: "tx_1"))
    end
    let(:applied_tax) { create(:invoice_applied_tax, invoice:, tax:, fees_amount_cents: 900) }
    let(:custom_section) { create(:applied_invoice_custom_section, invoice:) }
    let(:error_detail) { create(:error_detail, owner: invoice, error_code: "tax_error", details: {"code" => "x"}) }

    before do
      create(:billing_segment, organization:, customer:, contract:, invoice:)
      later_fee
      earlier_fee
      event_fee
      applied_tax
      custom_section
      error_detail
    end

    it "serializes the fees in creation order with the v2 fee shape" do
      expect(result["fees"].map { it["lago_id"] }).to eq([earlier_fee.id, later_fee.id, event_fee.id])
      expect(result["fees"].first).to include(
        "lago_invoice_id" => invoice.id,
        "lago_contract_id" => contract.id,
        "lago_product_id" => product.id,
        "product_code" => product.code
      )
      expect(result["fees"].first).not_to have_key("lago_subscription_id")
    end

    it "lists the distinct contracts the fees were billed from" do
      expect(invoice.contracts).to eq([contract])
      expect(result["contracts"]).to eq(
        [
          {"lago_id" => contract.id, "external_id" => contract.external_id},
          {"lago_id" => other_contract.id, "external_id" => other_contract.external_id}
        ]
      )
    end

    it "serializes the applied taxes without a currency" do
      expect(result["applied_taxes"]).to eq(
        [
          {
            "lago_id" => applied_tax.id,
            "lago_invoice_id" => invoice.id,
            "lago_tax_id" => tax.id,
            "tax_name" => "VAT",
            "tax_code" => tax.code,
            "tax_rate" => 20.0,
            "tax_description" => "French Standard VAT",
            "amount_cents" => 200,
            "fees_amount_cents" => 900,
            "created_at" => applied_tax.created_at.iso8601
          }
        ]
      )
    end

    it "serializes the custom sections and error details" do
      expect(result["applied_invoice_custom_sections"]).to eq(
        [
          {
            "lago_id" => custom_section.id,
            "lago_invoice_id" => invoice.id,
            "code" => custom_section.code,
            "details" => custom_section.details,
            "display_name" => custom_section.display_name,
            "created_at" => custom_section.created_at.iso8601
          }
        ]
      )
      expect(result["error_details"]).to eq(
        [{"lago_id" => error_detail.id, "error_code" => "tax_error", "details" => {"code" => "x"}}]
      )
    end
  end
end
