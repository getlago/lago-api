# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentsController do
  let(:invoice) { create(:invoice, payment_due_date: Date.current) }

  before do
    invoice.file.attach(
      io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
      filename: "invoice.pdf",
      content_type: "application/pdf"
    )
  end

  def document_path_for(url)
    URI.parse(url).path
  end

  describe "GET /documents/:signed_id/*filename" do
    it "redirects to the file while the link is valid" do
      get document_path_for(invoice.file_url)

      expect(response).to have_http_status(:redirect)
    end

    context "when the link has expired" do
      let!(:path) { document_path_for(invoice.file_url) }

      it "returns a JSON error for API clients" do
        travel_to(1.year.from_now) { get path, headers: {"Accept" => "application/json"} }

        expect(response).to have_http_status(:gone)
        expect(json).to eq(status: 410, error: "Gone", code: "expired")
      end

      it "returns a plain page for browsers" do
        travel_to(1.year.from_now) { get path, headers: {"Accept" => "text/html,application/xhtml+xml"} }

        expect(response).to have_http_status(:gone)
        expect(response.body).to include("This link has expired.")
      end
    end

    it "returns not found for a tampered link" do
      get "/documents/not-a-signed-id/invoice.pdf"

      expect(response).to be_not_found_error("resource")
    end

    it "returns not found for a link signed for another purpose" do
      get "/documents/#{invoice.file.blob.signed_id}/invoice.pdf"

      expect(response).to be_not_found_error("resource")
    end

    it "returns not found for an expired link whose file is gone" do
      path = document_path_for(invoice.file_url)
      invoice.file.purge

      travel_to(1.year.from_now) { get path, headers: {"Accept" => "application/json"} }

      expect(response).to be_not_found_error("resource")
    end

    it "returns not found for a valid link whose file is gone" do
      path = document_path_for(invoice.file_url)
      invoice.file.purge

      get path

      expect(response).to be_not_found_error("resource")
    end
  end

  describe "legacy Active Storage links" do
    let(:legacy_path) { Rails.application.routes.url_helpers.rails_blob_path(invoice.file, only_path: true) }

    it "keeps working while no cutoff is set" do
      get legacy_path

      expect(response).to have_http_status(:redirect)
    end

    context "when the cutoff is in the future" do
      around do |test|
        Rails.application.config.x.legacy_document_urls_expire_at = 1.day.from_now
        test.run
      ensure
        Rails.application.config.x.legacy_document_urls_expire_at = nil
      end

      it "keeps serving document blobs" do
        get legacy_path

        expect(response).to have_http_status(:redirect)
      end
    end

    context "when the cutoff has passed" do
      around do |test|
        Rails.application.config.x.legacy_document_urls_expire_at = Time.zone.parse("2026-01-01")
        test.run
      ensure
        Rails.application.config.x.legacy_document_urls_expire_at = nil
      end

      it "refuses document blobs" do
        get legacy_path, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:gone)
        expect(json[:code]).to eq("expired")
      end

      it "refuses document blobs through the proxy route" do
        get Rails.application.routes.url_helpers.rails_storage_proxy_path(invoice.file, only_path: true),
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:gone)
      end

      it "refuses every document type" do
        pdf = -> { {io: File.open(Rails.root.join("spec/fixtures/blank.pdf")), filename: "document.pdf"} }
        credit_note = create(:credit_note)
        credit_note.file.attach(**pdf.call)
        payment_receipt = create(:payment_receipt)
        payment_receipt.file.attach(**pdf.call)
        order_form = create(:order_form, :signed, :with_signed_document)

        [credit_note.file, payment_receipt.file, order_form.signed_document].each do |attachment|
          get Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true),
            headers: {"Accept" => "application/json"}

          expect(response).to have_http_status(:gone), "expected #{attachment.record_type} to be refused"
        end
      end

      it "still serves logos" do
        organization = invoice.organization
        organization.logo.attach(
          io: StringIO.new(File.read(Rails.root.join("spec/factories/images/logo.png"))),
          filename: "logo.png",
          content_type: "image/png"
        )

        get Rails.application.routes.url_helpers.rails_blob_path(organization.logo, only_path: true)

        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "legacy cutoff configuration" do
    def load_initializer(value)
      stub_const("ENV", ENV.to_h.merge("LAGO_LEGACY_DOCUMENT_URLS_EXPIRE_AT" => value))
      load Rails.root.join("config/initializers/legacy_document_urls.rb")
    ensure
      Rails.application.config.x.legacy_document_urls_expire_at = nil
    end

    it "fails at boot on a malformed date" do
      expect { load_initializer("2026-13-01") }.to raise_error(ArgumentError, /LAGO_LEGACY_DOCUMENT_URLS_EXPIRE_AT/)
      expect { load_initializer("not a date") }.to raise_error(ArgumentError, /LAGO_LEGACY_DOCUMENT_URLS_EXPIRE_AT/)
    end

    it "parses a valid date" do
      stub_const("ENV", ENV.to_h.merge("LAGO_LEGACY_DOCUMENT_URLS_EXPIRE_AT" => "2027-01-01"))
      load Rails.root.join("config/initializers/legacy_document_urls.rb")

      expect(Rails.application.config.x.legacy_document_urls_expire_at).to eq(Time.utc(2027, 1, 1))
    ensure
      Rails.application.config.x.legacy_document_urls_expire_at = nil
    end
  end
end
