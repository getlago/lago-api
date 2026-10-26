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
      "sub_total_excluding_taxes_amount_cents" => 900,
      "taxes_amount_cents" => 180,
      "sub_total_including_taxes_amount_cents" => 1_080,
      "credit_notes_amount_cents" => 0,
      "total_amount_cents" => 1_080,
      "total_offsetted_credit_note_amount_cents" => 0,
      "total_paid_amount_cents" => 80,
      "total_due_amount_cents" => 1_000,
      "pdf_url" => nil,
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

  context "with every expansion" do
    let(:includes) { described_class.expandable_names }
    let(:tax) { create(:tax, organization:) }
    let(:other_contract) { create(:contract, organization:, customer:) }
    let(:rate_card) { create(:rate_card, organization:, product:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
    let(:other_contract_rate_card) { create(:contract_rate_card, organization:, contract: other_contract, rate_card:) }
    let(:fee_attributes) do
      {invoice:, subscription: nil, fee_type: :product, invoiceable: product, contract:, contract_rate_card:, rate_card_rate:}
    end
    let(:later_fee) { create(:fee, fee_attributes.merge(created_at: 1.hour.ago)) }
    let(:earlier_fee) { create(:fee, fee_attributes.merge(created_at: 2.hours.ago)) }
    let(:event_fee) do
      create(
        :fee,
        fee_attributes.merge(
          contract: other_contract,
          contract_rate_card: other_contract_rate_card,
          pay_in_advance: true,
          pay_in_advance_event_transaction_id: "tx_1"
        )
      )
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

    it "adds the expansions after the invoice, in their declared order" do
      expect(result.keys.last(6)).to eq(%w[fees applied_taxes customer contracts applied_invoice_custom_sections error_details])
      expect(result["customer"]).to eq(JSON.parse(V2::CustomerSerializer.new(customer).serialize.to_json))
    end

    it "serializes the fees in creation order with the flat v2 fee shape" do
      expect(result["fees"].map { it["lago_id"] }).to eq([earlier_fee.id, later_fee.id, event_fee.id])
      expect(result["fees"].first).to include(
        "lago_invoice_id" => invoice.id,
        "lago_contract_id" => contract.id,
        "lago_product_id" => product.id,
        "product_code" => product.code
      )
      expect(result["fees"].first).not_to have_key("lago_subscription_id")
      expect(result["fees"].first).not_to have_key("applied_taxes")
    end

    context "with the contracts only" do
      let(:includes) { %i[contracts] }
      let(:contract) { create(:contract, organization:, customer:, catalog_plan: create(:catalog_plan, organization:)) }
      let(:other_contract) { create(:contract, organization:, customer: create(:customer, organization:), catalog_plan: create(:catalog_plan, organization:)) }

      it "loads the customers, billing entities and plans of all the contracts at once" do
        tables = []
        callback = ->(*, payload) { tables << payload[:sql][/FROM "(customers|billing_entities|#{CatalogPlan.table_name})"/, 1] }

        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { result }

        expect(result["contracts"].size).to eq(2)
        expect(tables.compact.tally).to eq("customers" => 1, "billing_entities" => 1, CatalogPlan.table_name => 1)
      end
    end

    context "with the fees of a deleted product" do
      let(:includes) { %i[fees] }

      before { Product.find(product.id).discard! }

      it "loads the product and its category once for all the fees" do
        tables = []
        callback = ->(*, payload) { tables << payload[:sql][/FROM "(products|product_categories)"/, 1] }

        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { result }

        expect(result["fees"].map { it["product_code"] }).to eq([product.code] * 3)
        expect(tables.compact.tally).to eq("products" => 1, "product_categories" => 1)
      end
    end

    it "lists the distinct contracts the fees were billed from" do
      expect(invoice.contracts).to eq([contract])
      expect(result["contracts"]).to eq(
        [contract, other_contract].map { JSON.parse(V2::ContractSerializer.new(it).serialize.to_json) }
      )
    end

    it "serializes the tax lines without a currency" do
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
            "created_at" => applied_tax.created_at.iso8601,
            "updated_at" => applied_tax.updated_at.iso8601
          }
        ]
      )
    end

    context "when the invoice also holds a legacy fee" do
      let(:includes) { %i[fees] }

      before { create(:fee, invoice:) }

      it "expands its product fees only" do
        expect(result["fees"].map { it["lago_id"] }).to eq([earlier_fee.id, later_fee.id, event_fee.id])
      end
    end

    context "with several applied taxes, custom sections and error details" do
      let(:earlier_tax) { create(:invoice_applied_tax, invoice:, tax: create(:tax, organization:), created_at: 1.day.ago) }
      let(:earlier_section) { create(:applied_invoice_custom_section, invoice:, created_at: 1.day.ago) }
      let(:earlier_error) { create(:error_detail, owner: invoice, error_code: "tax_voiding_error", created_at: 1.day.ago) }

      before do
        earlier_tax
        earlier_section
        earlier_error
      end

      it "lists each collection in creation order" do
        expect(result["applied_taxes"].map { it["lago_id"] }).to eq([earlier_tax.id, applied_tax.id])
        expect(result["applied_invoice_custom_sections"].map { it["lago_id"] }).to eq([earlier_section.id, custom_section.id])
        expect(result["error_details"].map { it["lago_id"] }).to eq([earlier_error.id, error_detail.id])
      end
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
            "created_at" => custom_section.created_at.iso8601,
            "updated_at" => custom_section.updated_at.iso8601
          }
        ]
      )
      expect(result["error_details"]).to eq(
        [
          {
            "lago_id" => error_detail.id,
            "error_code" => "tax_error",
            "details" => {"code" => "x"},
            "created_at" => error_detail.created_at.iso8601,
            "updated_at" => error_detail.updated_at.iso8601,
            "deleted_at" => nil
          }
        ]
      )
    end

    context "with the webhook includes" do
      let(:includes) { described_class::WEBHOOK_INCLUDES }

      it "leaves the fees and the customer out" do
        expect(result.keys.last(4)).to eq(%w[applied_taxes contracts applied_invoice_custom_sections error_details])
      end
    end
  end
end
