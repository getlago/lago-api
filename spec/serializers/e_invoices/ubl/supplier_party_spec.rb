# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::SupplierParty do
  subject do
    xml_document(:ubl) do |xml|
      described_class.serialize(xml:, resource:, options:)
    end
  end

  let(:options) { described_class::Options.new }
  let(:resource) { invoice }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invoice) { create(:invoice, organization:, billing_entity:, invoice_type:) }
  let(:invoice_type) { :subscription }
  let(:billing_entity) do
    create(:billing_entity,
      organization:,
      code: "BE_CODE",
      legal_name: "BE Legal Name",
      zipcode: "60192460",
      address_line1: "Rue quelque part",
      address_line2: "Tourne au deuxième angle",
      city: "Eine Stadt",
      country: "BR",
      tax_identification_number: "BR987654321")
  end

  let(:root) { "//cac:AccountingSupplierParty/cac:Party" }

  before { invoice }

  describe ".serialize" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Supplier Party")
    end

    context "with billing entity" do
      context "with PostalAddress" do
        let(:xpath) { "#{root}/cac:PostalAddress" }

        it "expects to have street name" do
          expect(subject).to contains_xml_node("#{xpath}/cbc:StreetName").with_value(billing_entity.address_line1)
          expect(subject).to contains_xml_node("#{xpath}/cbc:AdditionalStreetName").with_value(billing_entity.address_line2)
        end

        it "expects to have city" do
          expect(subject).to contains_xml_node("#{xpath}/cbc:CityName").with_value(billing_entity.city)
        end

        it "expects to have zipcode" do
          expect(subject).to contains_xml_node("#{xpath}/cbc:PostalZone").with_value(billing_entity.zipcode)
        end

        it "expects to have country" do
          expect(subject).to contains_xml_node("#{xpath}/cac:Country/cbc:IdentificationCode")
            .with_value(billing_entity.country)
        end
      end

      context "with PartyTaxScheme" do
        let(:xpath) { "#{root}/cac:PartyTaxScheme" }

        it "expects to have company id" do
          expect(subject).to contains_xml_node("#{xpath}/cbc:CompanyID").with_value(billing_entity.tax_identification_number)
        end

        it "expects to have tax scheme id" do
          expect(subject).to contains_xml_node("#{xpath}/cac:TaxScheme/cbc:ID").with_value("VAT")
        end

        context "with tax_registration as false" do
          let(:options) { described_class::Options.new(tax_registration: false) }

          it "does not have the tag" do
            expect(subject).not_to contains_xml_node("#{root}/cac:PartyTaxScheme")
          end
        end
      end

      context "with PartyLegalEntity" do
        let(:xpath) { "#{root}/cac:PartyLegalEntity" }

        it "expects to have registration name" do
          expect(subject).to contains_xml_node("#{xpath}/cbc:RegistrationName").with_value(billing_entity.legal_name)
        end

        it "expects to have company id" do
          expect(subject).to contains_xml_node("#{xpath}/cbc:CompanyID").with_value(billing_entity.tax_identification_number)
        end
      end
    end
  end
end
