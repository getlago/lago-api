# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::PaymentReceiptSerializer do
  subject(:payload) { described_class.new(payment_receipt, includes:).serialize }

  let(:includes) { [] }
  let(:payment_receipt) { create(:payment_receipt) }

  around { |example| freeze_time { example.run } }

  it "serializes the receipt with its payment, and no document link before generation" do
    expect(payload).to eq(
      lago_id: payment_receipt.id,
      number: payment_receipt.number,
      lago_payment_id: payment_receipt.payment_id,
      pdf_url: nil,
      pdf_url_expires_at: nil,
      xml_url: nil,
      xml_url_expires_at: nil,
      created_at: payment_receipt.created_at.iso8601,
      updated_at: payment_receipt.updated_at.iso8601
    )
  end

  context "with the payment expansion" do
    let(:includes) { [:payment] }
    let(:payment) { payment_receipt.payment }

    it "embeds the payment" do
      expect(payload[:payment]).to eq(
        lago_id: payment.id,
        lago_customer_id: payment.customer_id,
        external_customer_id: payment.customer.external_id,
        lago_payable_id: payment.payable_id,
        payable_type: "Invoice",
        lago_invoice_ids: [payment.payable_id],
        amount_cents: payment.amount_cents,
        currency: payment.amount_currency,
        status: payment.status,
        payment_status: payment.payable_payment_status,
        payment_type: "provider",
        reference: payment.reference,
        payment_provider_code: payment.payment_provider.code,
        payment_provider_type: "stripe",
        provider_payment_id: payment.provider_payment_id,
        provider_customer_id: payment.payment_provider_customer.provider_customer_id,
        next_action: payment.provider_payment_data,
        created_at: payment.created_at.iso8601,
        updated_at: payment.updated_at.iso8601
      )
    end
  end

  context "when the PDF and the XML are generated" do
    before do
      payment_receipt.file.attach(io: File.open(Rails.root.join("spec/fixtures/blank.pdf")), filename: "receipt.pdf", content_type: "application/pdf")
      payment_receipt.xml_file.attach(io: File.open(Rails.root.join("spec/fixtures/blank.xml")), filename: "receipt.xml", content_type: "application/xml")
    end

    it "links both documents" do
      expect(payload).to eq(
        lago_id: payment_receipt.id,
        number: payment_receipt.number,
        lago_payment_id: payment_receipt.payment_id,
        pdf_url: payment_receipt.file_url,
        pdf_url_expires_at: payment_receipt.file_url_expires_at.iso8601,
        xml_url: payment_receipt.xml_url,
        xml_url_expires_at: payment_receipt.xml_url_expires_at.iso8601,
        created_at: payment_receipt.created_at.iso8601,
        updated_at: payment_receipt.updated_at.iso8601
      )
    end

    it "serializes preloaded documents without extra queries" do
      receipt = PaymentReceipt.preload(described_class::PRELOADS).find(payment_receipt.id)

      queries = capture_sql { described_class.new(receipt).serialize }

      expect(queries).to be_empty
    end

    context "with API v2 timestamps" do
      let(:includes) { [:usec_timestamps] }

      it "formats the document expiry to the microsecond" do
        expect(payload[:pdf_url_expires_at]).to eq(payment_receipt.file_url_expires_at.iso8601(6))
        expect(payload[:xml_url_expires_at]).to eq(payment_receipt.xml_url_expires_at.iso8601(6))
      end
    end
  end
end
