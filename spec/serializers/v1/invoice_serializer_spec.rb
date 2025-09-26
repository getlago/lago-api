# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::InvoiceSerializer do
  subject(:serializer) { described_class.new(invoice, root_name: "invoice", includes:) }

  let(:includes) { %i[metadata error_details] }

  let(:invoice) do
    create(
      :invoice,
      customer_data_snapshotted_at: Time.current,
      customer_display_name: "John Doe",
      customer_firstname: "John",
      customer_lastname: "Doe",
      customer_email: "john.doe@example.com",
      customer_phone: "+1234567890",
      customer_url: "https://john.doe.com",
      customer_tax_identification_number: "1234567890",
      customer_applicable_timezone: "UTC",
      customer_address_line1: "123 Main St",
      customer_address_line2: "Apt 1",
      customer_city: "New York",
      customer_state: "NY",
      customer_zipcode: "10001",
      customer_country: "US",
      customer_legal_name: "John Doe",
      customer_legal_number: "1234567890",
      customer_shipping_address_line1: "Rue de la Paix",
      customer_shipping_address_line2: "Apt 5B",
      customer_shipping_city: "Paris",
      customer_shipping_state: "Ile-de-France",
      customer_shipping_zipcode: "75000",
      customer_shipping_country: "FR"
    )
  end

  let(:metadata) { create(:invoice_metadata, invoice:) }
  let(:error_details1) { create(:error_detail, owner: invoice) }
  let(:error_details2) { create(:error_detail, owner: invoice, deleted_at: Time.current) }

  before do
    metadata
    error_details1
    error_details2
  end

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result["invoice"]).to include(
        "lago_id" => invoice.id,
        "billing_entity_code" => invoice.billing_entity.code,
        "sequential_id" => invoice.sequential_id,
        "number" => invoice.number,
        "issuing_date" => invoice.issuing_date.iso8601,
        "payment_due_date" => invoice.payment_due_date.iso8601,
        "net_payment_term" => invoice.net_payment_term,
        "invoice_type" => invoice.invoice_type,
        "status" => invoice.status,
        "payment_status" => invoice.payment_status,
        "payment_dispute_lost_at" => invoice.payment_dispute_lost_at,
        "payment_overdue" => invoice.payment_overdue,
        "currency" => invoice.currency,
        "fees_amount_cents" => invoice.fees_amount_cents,
        "progressive_billing_credit_amount_cents" => invoice.progressive_billing_credit_amount_cents,
        "coupons_amount_cents" => invoice.coupons_amount_cents,
        "credit_notes_amount_cents" => invoice.credit_notes_amount_cents,
        "prepaid_credit_amount_cents" => invoice.prepaid_credit_amount_cents,
        "taxes_amount_cents" => invoice.taxes_amount_cents,
        "sub_total_excluding_taxes_amount_cents" => invoice.sub_total_excluding_taxes_amount_cents,
        "sub_total_including_taxes_amount_cents" => invoice.sub_total_including_taxes_amount_cents,
        "total_amount_cents" => invoice.total_amount_cents,
        "total_due_amount_cents" => invoice.total_due_amount_cents,
        "file_url" => invoice.file_url,
        "error_details" => [
          {
            "lago_id" => error_details1.id,
            "error_code" => error_details1.error_code,
            "details" => error_details1.details
          }
        ],
        "version_number" => 4,
        "self_billed" => invoice.self_billed,
        "created_at" => invoice.created_at.iso8601,
        "updated_at" => invoice.updated_at.iso8601,
        "customer_data_snapshotted_at" => invoice.customer_data_snapshotted_at.iso8601,
        "customer_display_name" => invoice.customer_display_name,
        "customer_firstname" => invoice.customer_firstname,
        "customer_lastname" => invoice.customer_lastname,
        "customer_email" => invoice.customer_email,
        "customer_phone" => invoice.customer_phone,
        "customer_url" => invoice.customer_url,
        "customer_tax_identification_number" => invoice.customer_tax_identification_number,
        "customer_applicable_timezone" => invoice.customer_applicable_timezone,
        "customer_address_line1" => invoice.customer_address_line1,
        "customer_address_line2" => invoice.customer_address_line2,
        "customer_city" => invoice.customer_city,
        "customer_state" => invoice.customer_state,
        "customer_zipcode" => invoice.customer_zipcode,
        "customer_country" => invoice.customer_country,
        "customer_legal_name" => invoice.customer_legal_name,
        "customer_legal_number" => invoice.customer_legal_number,
        "customer_shipping_address" => {
          "address_line1" => invoice.customer_shipping_address_line1,
          "address_line2" => invoice.customer_shipping_address_line2,
          "city" => invoice.customer_shipping_city,
          "state" => invoice.customer_shipping_state,
          "zipcode" => invoice.customer_shipping_zipcode,
          "country" => invoice.customer_shipping_country
        }
      )

      expect(result["invoice"]["metadata"].first).to include(
        "lago_id" => metadata.id,
        "key" => metadata.key,
        "value" => metadata.value
      )
    end
  end

  context "when invoice is a progressive_billing invoice" do
    let(:invoice) { create(:invoice, invoice_type: :progressive_billing) }
    let(:applied_usage_threshold) { create(:applied_usage_threshold, invoice:) }

    before { applied_usage_threshold }

    it "serializes the object" do
      result = JSON.parse(serializer.to_json)

      expect(result["invoice"]["applied_usage_thresholds"].count).to eq(1)
    end
  end

  context "when including billing periods" do
    let(:includes) { %i[billing_periods] }
    let(:invoice_subscription) { create(:invoice_subscription, :boundaries, invoice:) }

    before { invoice_subscription }

    it "serializes the invoice_subscription" do
      result = JSON.parse(serializer.to_json)

      expect(result["invoice"]["billing_periods"]).to be_present
    end
  end

  context "when the tax was deleted" do
    let(:includes) { %i[applied_taxes] }

    it "still return the tax_id" do
      organization = invoice.organization
      tax = create(:tax, organization:)
      create(:invoice_applied_tax, invoice:, tax:)

      tax.discard!
      invoice.reload
      result = JSON.parse(serializer.to_json)

      expect(result["invoice"]["applied_taxes"].sole["lago_tax_id"]).to be_present
    end
  end
end
