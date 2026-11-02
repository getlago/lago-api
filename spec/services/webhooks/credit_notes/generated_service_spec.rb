# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::CreditNotes::GeneratedService do
  subject(:webhook_service) { described_class.new(object: credit_note) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:credit_note) { create(:credit_note, :with_metadata, customer:, invoice:) }

  describe ".call", :bullet do
    it_behaves_like "creates webhook", "credit_note.generated", "credit_note", {
      "customer" => Hash,
      "metadata" => {"key" => "value"}
    }

    it "keeps the complete legacy payload for subscription credit notes" do
      webhook_service.call

      expect(Webhook.order(created_at: :desc).first.payload["credit_note"]).to eq(legacy_payload)
    end

    context "when the invoice is from the product catalog" do
      let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }

      it "sends the v2 credit note with its webhook expansions" do
        webhook_service.call

        body = Webhook.order(created_at: :desc).first.payload["credit_note"]
        expect(body).to eq(catalog_payload)
      end
    end
  end

  def legacy_payload
    {
      "lago_id" => credit_note.id,
      "billing_entity_code" => invoice.billing_entity.code,
      "sequential_id" => credit_note.sequential_id,
      "number" => credit_note.number,
      "lago_invoice_id" => invoice.id,
      "invoice_number" => invoice.number,
      "purchase_order_number" => credit_note.purchase_order_number,
      "issuing_date" => credit_note.issuing_date.iso8601,
      "credit_status" => credit_note.credit_status,
      "refund_status" => credit_note.refund_status,
      "reason" => credit_note.reason,
      "description" => credit_note.description,
      "currency" => credit_note.currency,
      "total_amount_cents" => credit_note.total_amount_cents,
      "precise_total_amount_cents" => credit_note.precise_total&.to_s,
      "taxes_amount_cents" => credit_note.taxes_amount_cents,
      "precise_taxes_amount_cents" => credit_note.precise_taxes_amount_cents&.to_s,
      "sub_total_excluding_taxes_amount_cents" => credit_note.sub_total_excluding_taxes_amount_cents,
      "balance_amount_cents" => credit_note.balance_amount_cents,
      "credit_amount_cents" => credit_note.credit_amount_cents,
      "refund_amount_cents" => credit_note.refund_amount_cents,
      "offset_amount_cents" => credit_note.offset_amount_cents,
      "coupons_adjustment_amount_cents" => credit_note.coupons_adjustment_amount_cents,
      "taxes_rate" => credit_note.taxes_rate,
      "created_at" => credit_note.created_at.iso8601,
      "updated_at" => credit_note.updated_at.iso8601,
      "file_url" => credit_note.file_url,
      "file_url_expires_at" => credit_note.file_url_expires_at&.iso8601,
      "xml_url" => credit_note.xml_url,
      "xml_url_expires_at" => credit_note.xml_url_expires_at&.iso8601,
      "self_billed" => invoice.self_billed,
      "customer" => V1::CustomerSerializer.new(customer).serialize.deep_stringify_keys,
      "metadata" => {"key" => "value"}
    }
  end

  def catalog_payload
    {
      "lago_id" => credit_note.id,
      "billing_entity_code" => invoice.billing_entity.code,
      "sequential_id" => credit_note.sequential_id,
      "number" => credit_note.number,
      "lago_invoice_id" => invoice.id,
      "invoice_number" => invoice.number,
      "purchase_order_number" => credit_note.purchase_order_number,
      "issuing_date" => credit_note.issuing_date.iso8601,
      "credit_status" => credit_note.credit_status,
      "refund_status" => credit_note.refund_status,
      "reason" => credit_note.reason,
      "description" => credit_note.description,
      "currency" => credit_note.currency,
      "sub_total_excluding_taxes_amount_cents" => credit_note.sub_total_excluding_taxes_amount_cents,
      "taxes_amount_cents" => credit_note.taxes_amount_cents,
      "sub_total_including_taxes_amount_cents" => credit_note.sub_total_excluding_taxes_amount_cents +
        credit_note.taxes_amount_cents,
      "total_amount_cents" => credit_note.total_amount_cents,
      "balance_amount_cents" => credit_note.balance_amount_cents,
      "credit_amount_cents" => credit_note.credit_amount_cents,
      "refund_amount_cents" => credit_note.refund_amount_cents,
      "offset_amount_cents" => credit_note.offset_amount_cents,
      "created_at" => credit_note.created_at.iso8601,
      "updated_at" => credit_note.updated_at.iso8601,
      "file_url" => credit_note.file_url,
      "xml_url" => credit_note.xml_url,
      "self_billed" => invoice.self_billed,
      "customer" => V2::CustomerSerializer.new(customer).serialize.deep_stringify_keys,
      "items" => [],
      "applied_taxes" => [],
      "metadata" => {"key" => "value"}
    }
  end
end
