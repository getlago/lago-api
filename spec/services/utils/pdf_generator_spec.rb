# frozen_string_literal: true

require "rails_helper"

RSpec.describe Utils::PdfGenerator do
  subject(:generate_pdf) { I18n.with_locale(locale) { pdf_generator_service.call } }

  let(:pdf_generator_service) { described_class.new(template: "invoices/v2", context: invoice) }
  let(:invoice) { create(:invoice, number: "INV-123 <&>") }
  let(:locale) { :en }
  let(:request_bodies) { [] }
  let(:request_body) { request_bodies.first }
  let(:pdf_response) do
    File.read(Rails.root.join("spec/fixtures/blank.pdf"))
  end

  before do
    stub_request(:post, "#{ENV["LAGO_PDF_URL"]}/forms/chromium/convert/html")
      .with { |request| request_bodies << request.body }
      .to_return(body: pdf_response, status: 200)
  end

  describe ".call" do
    it "generated the document synchronously" do
      expect(generate_pdf.io).to be_present
    end

    it "adds a footer with the document number and page counters" do
      generate_pdf

      expect(request_body).to include('name="file3"; filename="footer.html"')
      expect(request_body).to include("INV-123 &lt;&amp;&gt;")
      expect(request_body).to include('<span class="pageNumber"></span>')
      expect(request_body).to include('<span class="totalPages"></span>')
    end

    context "with a French document locale" do
      let(:locale) { :fr }

      it "uses the localized page counter order" do
        generate_pdf

        expect(request_body).to include(
          'Page <span class="pageNumber"></span> sur <span class="totalPages"></span>'
        )
      end
    end

    context "with a credit note" do
      let(:pdf_generator_service) do
        described_class.new(template: "credit_notes/credit_note", context: credit_note)
      end
      let(:credit_note) { create(:credit_note, number: "CN-123") }

      it "adds its number to the footer" do
        generate_pdf

        expect(request_body).to match(/filename="footer\.html".*CN-123/m)
      end
    end
  end
end
