# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::CreateService, type: :service do
  subject(:result) { described_class.call(organization:, params:) }

  let(:organization) { create :organization }
  let(:params) do
    {
      name: "Billing Entity",
      code: "billing-entity"
    }
  end

  context "when lago freemium" do
    it "returns an error" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end

    context "when the organization does not have active billing entities" do
      before do
        organization.billing_entities.each(&:discard)
      end

      it "creates a billing entity" do
        expect(result).to be_success
        expect(result.billing_entity).to be_persisted
        expect(result.billing_entity.name).to eq("Billing Entity")
        expect(result.billing_entity.code).to eq("billing-entity")
      end

      it "does not set premium attributes" do
        params.merge!(
          {
            timezone: "Europe/Paris",
            email_settings: ["invoice.finalized"],
            billing_configuration: {invoice_grace_period: 15}
          }
        )

        expect(result).to be_success
        expect(result.billing_entity).to be_persisted
        expect(result.billing_entity.invoice_grace_period).to eq(0)
        expect(result.billing_entity.timezone).to eq("UTC")
        expect(result.billing_entity.email_settings).to be_empty
      end
    end
  end

  context "when lago premium" do
    around { |test| lago_premium!(&test) }

    context "when no multi_entity premium feature is enabled" do
      it "returns an error" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end
    end

    context "when multi_entities_pro premium feature is enabled" do
      let(:organization) do
        create(:organization, premium_integrations: ["multi_entities_pro"])
      end

      it "creates a billing entity" do
        expect(organization.billing_entities.count).to eq(1)
        expect(result).to be_success
        expect(result.billing_entity).to be_persisted
        expect(result.billing_entity.name).to eq("Billing Entity")
      end

      context "when creating billing entity with full data" do
        let(:params) do
          {
            name: "Billing Entity",
            code: "billing-entity",
            address_line1: "Address Line 1",
            address_line2: "Address Line 2",
            city: "City",
            country: "fr",
            default_currency: "CHF",
            document_number_prefix: "ENT-1234",
            document_numbering: "per_customer",
            email: "test@lago.com",
            finalize_zero_amount_invoice: true,
            legal_name: "Legal Name",
            legal_number: "Legal Number",
            net_payment_term: 90,
            state: "State",
            tax_identification_number: "EU123456789",
            vat_rate: 1,
            zipcode: "12345",
            timezone: "Europe/Paris",
            email_settings: ["invoice.finalized", "credit_note.created"],
            billing_configuration: {
              invoice_grace_period: 15,
              invoice_footer: "Invoice Footer",
              document_locale: "fr"
            },
            eu_tax_management: true,
            logo: "data:image/png;base64,#{Base64.encode64(File.read("spec/factories/images/logo.png"))}"
          }
        end

        before do
          allow(Taxes::AutoGenerateService).to receive(:call)
        end

        it "creates a billing entity with full data" do
          expect(result).to be_success
          expect(result.billing_entity).to be_persisted
          expect(result.billing_entity.name).to eq("Billing Entity")
          expect(result.billing_entity.address_line1).to eq("Address Line 1")
          expect(result.billing_entity.address_line2).to eq("Address Line 2")
          expect(result.billing_entity.city).to eq("City")
          expect(result.billing_entity.country).to eq("FR")
          expect(result.billing_entity.default_currency).to eq("CHF")
          expect(result.billing_entity.document_number_prefix).to eq("ENT-1234")
          expect(result.billing_entity.document_numbering).to eq("per_customer")
          expect(result.billing_entity.email).to eq("test@lago.com")
          expect(result.billing_entity.finalize_zero_amount_invoice).to eq(true)
          expect(result.billing_entity.legal_name).to eq("Legal Name")
          expect(result.billing_entity.legal_number).to eq("Legal Number")
          expect(result.billing_entity.net_payment_term).to eq(90)
          expect(result.billing_entity.state).to eq("State")
          expect(result.billing_entity.tax_identification_number).to eq("EU123456789")
          expect(result.billing_entity.vat_rate).to eq(1)
          expect(result.billing_entity.zipcode).to eq("12345")
          expect(result.billing_entity.timezone).to eq("Europe/Paris")
          expect(result.billing_entity.email_settings).to eq(["invoice.finalized", "credit_note.created"])
          expect(result.billing_entity.invoice_grace_period).to eq(15)
          expect(result.billing_entity.invoice_footer).to eq("Invoice Footer")
          expect(result.billing_entity.document_locale).to eq("fr")
          expect(result.billing_entity.eu_tax_management).to eq(true)
          expect(result.billing_entity.logo).to be_attached
          expect(Taxes::AutoGenerateService).to have_received(:call).with(organization:)
        end
      end

      context "when document_number_prefix is lowercase" do
        it "converts document_number_prefix to uppercase" do
          params[:document_number_prefix] = "abc"

          expect(result).to be_success
          expect(result.billing_entity.document_number_prefix).to eq("ABC")
        end
      end

      context "when document_number_prefix is invalid" do
        before { params[:document_number_prefix] = "aaaaaaaaaaaaaaa" }

        it "returns an error" do
          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:document_number_prefix]).to eq(["value_is_too_long"])
        end
      end

      context "when billing entity outside the EU and eu_tax_management is true" do
        let(:tax_auto_generate_service) { instance_double(Taxes::AutoGenerateService) }

        before do
          params[:country] = "us"
          params[:eu_tax_management] = true

          allow(Taxes::AutoGenerateService).to receive(:new).and_return(tax_auto_generate_service)
          allow(tax_auto_generate_service).to receive(:call)
        end

        it "returns an error" do
          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq({eu_tax_management: ["billing_entity_must_be_in_eu"]})
          expect(tax_auto_generate_service).not_to have_received(:call)
        end
      end

      context "with validation errors" do
        before do
          params[:country] = "---"
        end

        it "returns an error" do
          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:country]).to eq(["not_a_valid_country_code"])
        end
      end

      context "when max billing entities limit is reached" do
        it "returns an error" do
          create(:billing_entity, organization:)

          expect(organization.billing_entities.count).to eq(2)
          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
        end
      end
    end

    context "when multi_entities_enterprise premium feature is enabled" do
      let(:organization) do
        create(:organization, premium_integrations: ["multi_entities_enterprise"])
      end

      it "creates a billing entity" do
        create(:billing_entity, organization:)

        expect(organization.billing_entities.count).to eq(2)
        expect(result).to be_success
        expect(result.billing_entity).to be_persisted
        expect(result.billing_entity.name).to eq("Billing Entity")
      end

      context "when record is invalid" do
        let(:params) { {name: nil, code: nil} }

        it "returns an error" do
          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ValidationFailure)
        end
      end
    end
  end
end
