# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::BillingEntitiesController, type: :request do
  let(:billing_entity1) { create(:billing_entity) }
  let(:organization) { billing_entity1.organization }
  let(:billing_entity2) { create(:billing_entity, organization:) }
  let(:billing_entity3) { create(:billing_entity) }
  let(:billing_entity4) { create(:billing_entity, :deleted, organization:) }
  let(:billing_entity5) { create(:billing_entity, :archived, organization:) }

  describe "GET /api/v1/billing_entities" do
    subject do
      get_with_token(organization, "/api/v1/billing_entities")
    end

    before do
      billing_entity1
      billing_entity2
      billing_entity3
      billing_entity4
      billing_entity5
    end

    it "returns a list of active not archived billing entities" do
      subject
      expect(response).to be_successful
      expect(json[:billing_entities].count).to eq(2)
      expect(json[:billing_entities].map { |billing_entity| billing_entity[:lago_id] }).to include(billing_entity1.id, billing_entity2.id)
    end
  end

  describe "GET /api/v1/billing_entities/:code" do
    subject do
      get_with_token(organization, "/api/v1/billing_entities/#{billing_entity1.code}")
    end

    it "returns a billing entity" do
      subject
      expect(response).to be_successful
      expect(json[:billing_entity][:lago_id]).to eq(billing_entity1.id)
    end

    context "when the billing entity has applied taxes" do
      let(:tax) { create(:tax) }
      let(:applied_tax) { create(:billing_entity_applied_tax, billing_entity: billing_entity1, tax:) }

      before { applied_tax }

      it "returns the billing entity with the applied taxes" do
        subject
        expect(json[:billing_entity][:taxes].count).to eq(1)
      end
    end

    context "when the billing entity from another organization is requested" do
      subject do
        get_with_token(organization, "/api/v1/billing_entities/#{billing_entity3.code}")
      end

      it "returns a 404" do
        subject
        expect(response).to be_not_found
      end
    end

    context "when the billing entity is archived" do
      subject do
        get_with_token(organization, "/api/v1/billing_entities/#{billing_entity5.code}")
      end

      it "returns billing entity" do
        subject
        expect(response).to be_successful
        expect(json[:billing_entity][:lago_id]).to eq(billing_entity5.id)
      end
    end

    context "when the billing entity is deleted" do
      subject do
        get_with_token(organization, "/api/v1/billing_entities/#{billing_entity4.code}")
      end

      it "returns a 404" do
        subject
        expect(response).to be_not_found
      end
    end
  end

  describe "PUT /api/v1/billing_entities/:code" do
    subject do
      put_with_token(organization, "/api/v1/billing_entities/#{billing_entity_code}", update_params)
    end

    let(:billing_entity_code) { billing_entity1.code }

    let(:update_params) do
      {
        billing_entity: {
          name: "New Name",
          email: "new@email.com",
          legal_name: "New Legal Name",
          legal_number: "1234567890",
          tax_identification_number: "Tax-1234",
          address_line1: "Calle de la Princesa 1",
          address_line2: "Apt 1",
          city: "Barcelona",
          state: "Barcelona",
          zipcode: "08001",
          country: "ES",
          default_currency: "EUR",
          timezone: "Europe/Madrid",
          document_numbering: "per_billing_entity",
          document_number_prefix: "NEW-0001",
          finalize_zero_amount_invoice: true,
          net_payment_term: 10,
          eu_tax_management: true,
          logo: logo,
          email_settings: ["invoice.finalized", "credit_note.created"],
          billing_configuration: {
            invoice_footer: "New Invoice Footer",
            document_locale: "es",
            invoice_grace_period: 10
          }
        }
      }
    end

    let(:logo) do
      logo_file = File.read(Rails.root.join("spec/factories/images/logo.png"))
      base64_logo = Base64.encode64(logo_file)

      "data:image/png;base64,#{base64_logo}"
    end

    around { |test| lago_premium!(&test) }

    it "updates the billing entity" do
      subject

      expect(response).to be_successful
      expect(billing_entity1.reload.name).to eq("New Name")

      expect(json[:billing_entity][:name]).to eq("New Name")
      expect(json[:billing_entity][:email]).to eq("new@email.com")
      expect(json[:billing_entity][:legal_name]).to eq("New Legal Name")
      expect(json[:billing_entity][:legal_number]).to eq("1234567890")
      expect(json[:billing_entity][:tax_identification_number]).to eq("Tax-1234")
      expect(json[:billing_entity][:address_line1]).to eq("Calle de la Princesa 1")
      expect(json[:billing_entity][:address_line2]).to eq("Apt 1")
      expect(json[:billing_entity][:city]).to eq("Barcelona")
      expect(json[:billing_entity][:state]).to eq("Barcelona")
      expect(json[:billing_entity][:zipcode]).to eq("08001")
      expect(json[:billing_entity][:country]).to eq("ES")
      expect(json[:billing_entity][:default_currency]).to eq("EUR")
      expect(json[:billing_entity][:timezone]).to eq("Europe/Madrid")
      expect(json[:billing_entity][:document_numbering]).to eq("per_billing_entity")
      expect(json[:billing_entity][:document_number_prefix]).to eq("NEW-0001")
      expect(json[:billing_entity][:finalize_zero_amount_invoice]).to eq(true)
      expect(json[:billing_entity][:net_payment_term]).to eq(10)
      expect(json[:billing_entity][:eu_tax_management]).to eq(true)
      expect(json[:billing_entity][:email_settings]).to eq(["invoice.finalized", "credit_note.created"])
      expect(json[:billing_entity][:invoice_footer]).to eq("New Invoice Footer")
      expect(json[:billing_entity][:document_locale]).to eq("es")
      expect(json[:billing_entity][:invoice_grace_period]).to eq(10)
      expect(json[:billing_entity][:logo_url]).to match(%r{.*/rails/active_storage/blobs/redirect/.*/logo})
    end

    context "when the billing entity is not found" do
      let(:billing_entity_code) { "NON_EXISTING_CODE" }

      it "returns a 404" do
        subject
        expect(response).to be_not_found
      end
    end
  end

  describe "POST /api/v1/billing_entities/:code/manage_taxes" do
    subject do
      post_with_token(organization, "/api/v1/billing_entities/#{billing_entity_code}/manage_taxes", tax_codes: tax_codes)
    end

    let(:tax1) { create(:tax, organization:, code: "TAX_CODE_1") }
    let(:tax2) { create(:tax, organization:, code: "TAX_CODE_2") }

    context "when the billing entity is found" do
      let(:billing_entity_code) { billing_entity1.code }
      let(:tax_codes) { [tax1.code, tax2.code] }

      before do
        allow(BillingEntities::Taxes::ManageTaxesService).to receive(:call).and_call_original
      end

      it "returns a 200" do
        subject
        expect(response).to be_successful
      end

      it "updates the taxes" do
        subject
        expect(billing_entity1.taxes.count).to eq(2)
        expect(billing_entity1.taxes.map(&:code)).to include("TAX_CODE_1", "TAX_CODE_2")
      end

      it "calls the manage taxes service" do
        subject
        expect(BillingEntities::Taxes::ManageTaxesService).to have_received(:call).with(billing_entity: billing_entity1, tax_codes: tax_codes)
      end

      context "when the tax codes are not found" do
        let(:tax_codes) { ["TAX_CODE_1", "TAX_CODE_3"] }

        it "returns a 404" do
          subject
          expect(response).to be_not_found
        end
      end
    end

    context "when the billing entity is not found" do
      let(:billing_entity_code) { "NON_EXISTING_CODE" }
      let(:tax_codes) { ["TAX_CODE_1", "TAX_CODE_2"] }

      it "returns a 404" do
        subject
        expect(response).to be_not_found
      end
    end
  end
end
