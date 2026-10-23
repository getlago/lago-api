# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpiringDocumentUrl do
  let(:organization) { create(:organization) }
  let(:invoice) { create(:invoice, organization:, issuing_date: Date.new(2026, 10, 1), payment_due_date:) }
  let(:payment_due_date) { Date.new(2026, 10, 31) }

  before do
    travel_to(Time.zone.parse("2026-10-21 12:00:00"))
    invoice.file.attach(
      io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
      filename: "invoice.pdf",
      content_type: "application/pdf"
    )
  end

  after { travel_back }

  describe "#document_url_expires_at" do
    it "expires 30 days after the due date by default" do
      expect(invoice.document_url_expires_at).to eq(Date.new(2026, 11, 30).end_of_day)
    end

    context "without a due date" do
      let(:payment_due_date) { nil }

      it "expires 30 days after the issuing date" do
        expect(invoice.document_url_expires_at).to eq(Date.new(2026, 10, 31).end_of_day)
      end
    end

    context "when the organization sets a longer window" do
      before { organization.update!(document_url_expiration_days: 120) }

      it "uses the organization window" do
        expect(invoice.document_url_expires_at).to eq(Date.new(2027, 2, 28).end_of_day)
      end
    end

    context "when the window has already passed" do
      let(:payment_due_date) { Date.new(2026, 1, 1) }

      it "keeps the link valid for at least 10 days" do
        expect(invoice.document_url_expires_at).to eq(Date.new(2026, 10, 31).end_of_day)
      end
    end
  end

  describe "#file_url" do
    it "signs the blob with an expiry and the document purpose" do
      signed_id = invoice.file_url.split("/documents/").last.split("/").first

      expect(ActiveStorage::Blob.find_signed(signed_id, purpose: :document)).to eq(invoice.file.blob)
      expect(ActiveStorage::Blob.find_signed(signed_id)).to be_nil

      travel_to(Date.new(2026, 12, 1).beginning_of_day)
      expect(ActiveStorage::Blob.find_signed(signed_id, purpose: :document)).to be_nil
    end

    it "exposes the expiry next to the url" do
      expect(invoice.file_url_expires_at).to eq(invoice.document_url_expires_at)
      expect(invoice.xml_url_expires_at).to be_nil
    end
  end

  describe "other documents" do
    it "anchors credit notes on their issuing date" do
      credit_note = create(:credit_note, organization:, issuing_date: Date.new(2026, 10, 15))

      expect(credit_note.document_url_expires_at).to eq(Date.new(2026, 11, 14).end_of_day)
    end

    it "anchors payment receipts on their creation date" do
      receipt = create(:payment_receipt, organization:, created_at: Time.zone.parse("2026-10-20 08:00:00"))

      expect(receipt.document_url_expires_at).to eq(Date.new(2026, 11, 19).end_of_day)
    end
  end
end
