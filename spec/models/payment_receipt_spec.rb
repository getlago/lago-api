# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReceipt do
  subject(:payment_receipt) { build(:payment_receipt) }

  it do
    expect(subject).to belong_to(:payment)
    expect(subject).to belong_to(:organization)
    expect(subject).to belong_to(:billing_entity)
    expect(subject).to have_one_attached(:file)
    expect(subject).to have_one_attached(:xml_file)
  end

  describe "Scopes" do
    describe ".product_catalog" do
      subject(:scope) { described_class.product_catalog }

      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:catalog_invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
      let(:legacy_invoice) { create(:invoice, organization:, customer:, invoice_type: :subscription) }
      let(:catalog_receipt) { create(:payment_receipt, organization:, payment: create(:payment, payable: catalog_invoice)) }
      let(:legacy_receipt) { create(:payment_receipt, organization:, payment: create(:payment, payable: legacy_invoice)) }
      let(:catalog_request_receipt) do
        payment_request = create(:payment_request, organization:, customer:, invoices: [catalog_invoice, legacy_invoice])
        create(:payment_receipt, organization:, payment: create(:payment, payable: payment_request))
      end
      let(:legacy_request_receipt) do
        payment_request = create(:payment_request, organization:, customer:, invoices: [legacy_invoice])
        create(:payment_receipt, organization:, payment: create(:payment, payable: payment_request))
      end

      before do
        catalog_receipt
        legacy_receipt
        catalog_request_receipt
        legacy_request_receipt
      end

      it "returns the receipts of payments on catalog invoices, directly or through a payment request" do
        expect(scope).to match_array([catalog_receipt, catalog_request_receipt])
      end
    end
  end

  describe "#file_url" do
    before do
      payment_receipt.save!
      payment_receipt.file.attach(
        io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
        filename: "payment_receipt.pdf",
        content_type: "application/pdf"
      )
    end

    it "returns the file url" do
      file_url = payment_receipt.file_url

      expect(file_url).to be_present
      expect(file_url).to include(ENV["LAGO_API_URL"])
    end
  end

  describe "#xml_url" do
    before do
      payment_receipt.save!
      payment_receipt.xml_file.attach(
        io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.xml"))),
        filename: "payment_receipt.xml",
        content_type: "application/xml"
      )
    end

    it "returns the xml url" do
      xml_url = payment_receipt.xml_url

      expect(xml_url).to be_present
      expect(xml_url).to include(ENV["LAGO_API_URL"])
    end
  end
end
