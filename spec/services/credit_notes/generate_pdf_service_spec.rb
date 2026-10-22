# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::GeneratePdfService do
  subject(:credit_note_generate_service) { described_class.new(credit_note:, context:) }

  let_it_be(:organization, refind: true) { create(:organization, name: "LAGO") }
  let_it_be(:customer, refind: true) { create(:customer, organization:) }
  let_it_be(:invoice, refind: true) { create(:invoice, customer:, organization:) }
  let(:credit_note) { create(:credit_note, invoice:, customer:) }
  let(:fee) { create(:fee, invoice:) }
  let(:credit_note_item) { create(:credit_note_item, credit_note:, fee:) }
  let(:context) { nil }

  before do
    credit_note_item

    stub_pdf_generation
    allow(Utils::PdfGenerator).to receive(:call).and_call_original
  end

  describe ".call" do
    it "generates the credit note synchronously" do
      result = credit_note_generate_service.call

      expect(result.credit_note.file).to be_present
    end

    it "uses credit_note template" do
      credit_note_generate_service.call

      expect(Utils::PdfGenerator).to have_received(:call).with(template: "credit_notes/credit_note", context: credit_note)
    end

    it "produces an activity log" do
      result = credit_note_generate_service.call

      expect(Utils::ActivityLog).to have_produced("credit_note.generated").with(result.credit_note)
    end

    context "with a partially credited contract product fee" do
      let(:product) { create(:product, organization:, name: "Billed contract product") }
      let(:invoice_display_name) { "Contract product display name" }
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract: create(:contract, organization:, customer:),
          rate_card: create(:rate_card, organization:, product:))
      end
      let(:rate_card_rate) do
        create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card)
      end
      let(:fee) do
        create(:fee, invoice:, subscription: nil, fee_type: :product, invoiceable: product,
          invoice_display_name:, contract: contract_rate_card.contract,
          contract_rate_card:, rate_card_rate:, units: 8, amount_cents: 8000, precise_amount_cents: 8000,
          precise_unit_amount: 10, taxes_rate: 0, taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
      end
      let(:credit_note) { create(:credit_note, invoice:, customer:, total_amount_cents: 2000, taxes_amount_cents: 0) }
      let(:credit_note_item) do
        create(:credit_note_item, credit_note:, fee:, amount_cents: 2000, precise_amount_cents: 2000)
      end

      it "attaches a PDF containing the product display name and credited amount" do
        result = credit_note_generate_service.call

        expect(result.credit_note.file).to be_attached
        expect(result.credit_note.file.download.force_encoding(Encoding::UTF_8)).to include("Contract product display name", "€20.00")
      end

      context "without a fee display name" do
        let(:invoice_display_name) { nil }

        it "renders the product invoice name in the attached PDF" do
          result = credit_note_generate_service.call

          expect(result.credit_note.file.download.force_encoding(Encoding::UTF_8)).to include(product.invoice_name, "€20.00")
        end
      end
    end

    context "when credit note is for self billed invoice" do
      let(:invoice) { create(:invoice, :self_billed, customer:, organization:) }
      let(:credit_note) { create(:credit_note, invoice:, customer:) }

      it "uses self billed template" do
        credit_note_generate_service.call

        expect(Utils::PdfGenerator).to have_received(:call).with(template: "credit_notes/self_billed", context: credit_note)
      end
    end

    context "with preferred locale" do
      before do
        customer.update!(document_locale: "fr")

        allow(I18n).to receive(:with_locale).and_yield
      end

      it "sets the correct document locale" do
        credit_note_generate_service.call
        expect(I18n).to have_received(:with_locale).with(:fr)
      end
    end

    context "when creating temp files" do
      let(:pdf_tempfile) { instance_double(Tempfile).as_null_object }
      let(:blank_pdf_path) { Rails.root.join("spec/fixtures/blank.pdf") }

      before do
        allow(pdf_tempfile).to receive(:path).and_return(blank_pdf_path)
        allow(Tempfile).to receive(:new).and_call_original
        allow(Tempfile).to receive(:new).with([credit_note.number, ".pdf"]).and_return(pdf_tempfile)
      end

      it "unlink the pdf file at the end" do
        described_class.call(credit_note:, context:)

        expect(pdf_tempfile).to have_received(:unlink)
      end
    end

    context "when einvoicing is enabled" do
      let(:fake_xml) { "<xml>content</xml>" }
      let(:country) { nil }
      let(:create_xml_result) { EInvoices::CreditNotes::Cii::CreateService::Result.new.tap { |result| result.xml = fake_xml } }

      before do
        credit_note.billing_entity.update(country:, einvoicing: true)

        allow(EInvoices::CreditNotes::Cii::CreateService).to receive(:call).and_return(create_xml_result)
        allow(Utils::PdfAttachmentService).to receive(:call!)
      end

      context "with FR country" do
        let(:country) { "FR" }

        it "generates the invoice with attached cii xml synchronously" do
          result = described_class.call(credit_note:, context:)

          expect(EInvoices::CreditNotes::Cii::CreateService).to have_received(:call)
          expect(Utils::PdfAttachmentService).to have_received(:call!).with(
            file: kind_of(Tempfile),
            attachment_content: fake_xml,
            attachment_name: "factur-x.xml"
          )
          expect(result.credit_note.file).to be_present
        end

        context "with a partially credited contract product fee" do
          let(:attachment_calls) { [] }
          let(:product) { create(:product, organization:, name: "Billed contract product") }
          let(:contract_rate_card) do
            create(:contract_rate_card, organization:, contract: create(:contract, organization:, customer:),
              rate_card: create(:rate_card, organization:, product:))
          end
          let(:rate_card_rate) do
            create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card)
          end
          let(:fee) do
            create(:fee, invoice:, subscription: nil, fee_type: :product, invoiceable: product,
              contract: contract_rate_card.contract, contract_rate_card:, rate_card_rate:, units: 8,
              amount_cents: 8000, precise_amount_cents: 8000, precise_unit_amount: 10,
              taxes_rate: 0, taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
          end
          let(:credit_note) { create(:credit_note, invoice:, customer:, total_amount_cents: 2000, taxes_amount_cents: 0) }
          let(:credit_note_item) do
            create(:credit_note_item, credit_note:, fee:, amount_cents: 2000, precise_amount_cents: 2000)
          end

          before do
            allow(EInvoices::CreditNotes::Cii::CreateService).to receive(:call).and_call_original
            allow(Utils::PdfAttachmentService).to receive(:call!) do |**arguments|
              attachment_calls << arguments
            end
          end

          it "attaches the real CII XML with full billed quantity and partial credit amount" do
            described_class.call(credit_note:, context:)

            expect(EInvoices::CreditNotes::Cii::CreateService).to have_received(:call)
            expect(attachment_calls.first).to include(attachment_name: "factur-x.xml")

            xml = Nokogiri::XML(attachment_calls.first.fetch(:attachment_content))
            line = xml.at_xpath("//*[local-name()='IncludedSupplyChainTradeLineItem']")

            expect(line.at_xpath(".//*[local-name()='Name']").text).to eq("Billed contract product")
            expect(line.at_xpath(".//*[local-name()='BilledQuantity']").text).to eq("-8.0")
            expect(line.at_xpath(".//*[local-name()='LineTotalAmount']").text).to eq("-20.00")
          end
        end

        context "when attaching the CII XML fails" do
          let(:attachment_error) do
            BaseService::ThirdPartyFailure.new(
              Utils::PdfAttachmentService::Result.new,
              third_party: "pdfcpu",
              error_code: "failed",
              error_message: ""
            )
          end

          before do
            allow(Utils::PdfAttachmentService).to receive(:call!).and_raise(attachment_error)
          end

          it "fails PDF generation" do
            expect { credit_note_generate_service.call }.to raise_error(BaseService::ThirdPartyFailure)
          end
        end
      end
    end

    context "with not found credit_note" do
      let(:credit_note) { nil }
      let(:credit_note_item) { nil }

      it "returns a result with error" do
        result = credit_note_generate_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("credit_note_not_found")
      end
    end

    context "when credit_note is draft" do
      let(:credit_note) { create(:credit_note, :draft, invoice:, customer:) }

      it "returns a not found error" do
        result = credit_note_generate_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("credit_note_not_found")
      end
    end

    context "with already generated file" do
      before do
        credit_note.file.attach(
          io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
          filename: "credit_note.pdf",
          content_type: "application/pdf"
        )
      end

      it "does not generate the pdf" do
        allow(LagoHttpClient::Client).to receive(:new)

        credit_note_generate_service.call

        expect(LagoHttpClient::Client).not_to have_received(:new)
      end
    end

    context "when context is API" do
      let(:context) { "api" }

      it "calls the SendWebhook job" do
        expect do
          credit_note_generate_service.call
        end.to have_enqueued_job(SendWebhookJob)
      end
    end

    context "when context is admin" do
      let(:context) { "admin" }

      it "calls the SendWebhook job" do
        expect do
          credit_note_generate_service.call
        end.to have_enqueued_job(SendWebhookJob)
      end
    end
  end
end
