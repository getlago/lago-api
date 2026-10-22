# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::PaymentReceiptSerializer do
  subject(:serializer) do
    described_class.new(payment_receipt, root_name: "payment_receipt")
  end

  let(:payment_receipt) { create(:payment_receipt) }

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    expect(result["payment_receipt"]).to include(
      "lago_id" => payment_receipt.id,
      "number" => payment_receipt.number,
      "created_at" => payment_receipt.created_at.iso8601,
      "file_url" => payment_receipt.file_url,
      "xml_url" => payment_receipt.xml_url
    )

    expect(result["payment_receipt"]["payment"]).to include(
      "lago_id" => payment_receipt.payment.id,
      "amount_cents" => payment_receipt.payment.amount_cents,
      "amount_currency" => payment_receipt.payment.amount_currency
    )
  end

  context "when the number is only set in the database" do
    before { payment_receipt.number = nil }

    it "reads the number from the database" do
      result = JSON.parse(serializer.to_json)

      expect(result["payment_receipt"]["number"]).to eq(PaymentReceipt.find(payment_receipt.id).number)
    end
  end

  it "does not reload the preloaded organization" do
    payment_receipt.file.attach(io: File.open(Rails.root.join("spec/fixtures/blank.pdf")), filename: "receipt.pdf")
    receipt = PaymentReceipt.includes(:organization).find(payment_receipt.id)

    queries = capture_sql { described_class.new(receipt, root_name: "payment_receipt").serialize }

    expect(queries.grep(/FROM "organizations"/)).to be_empty
  end
end
