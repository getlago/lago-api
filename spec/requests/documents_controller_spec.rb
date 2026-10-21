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
  end

  describe "legacy Active Storage links" do
    let(:legacy_path) { Rails.application.routes.url_helpers.rails_blob_path(invoice.file, only_path: true) }

    it "keeps working while no cutoff is set" do
      get legacy_path

      expect(response).to have_http_status(:redirect)
    end

    context "when the cutoff has passed" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_LEGACY_DOCUMENT_URLS_EXPIRE_AT" => "2026-01-01")) }

      it "refuses document blobs" do
        get legacy_path, headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:gone)
        expect(json[:code]).to eq("expired")
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
end
