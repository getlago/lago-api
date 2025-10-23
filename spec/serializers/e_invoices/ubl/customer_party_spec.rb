# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::CustomerParty do
  subject do
    xml_document(:ubl) do |xml|
      described_class.serialize(xml:, resource:)
    end
  end

  let(:resource) { invoice }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:customer) do
    create(:customer,
      organization:,
      address_line1: "Streets of Tomorrow",
      address_line2: "on AC",
      city: "SP",
      zipcode: "123654789",
      country: "BR",
      name: "Andre")
  end

  let(:root) { "//cac:AccountingCustomerParty/cac:Party" }

  before { invoice }

  describe ".serialize" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Customer Party")
    end

    context "with customer" do
      context "with PostalAddress" do
        let(:xpath) { "#{root}/cac:PostalAddress" }

        it "expects to have street name" do
          expect(subject).to contains_xml_node("#{xpath}/cbc:StreetName").with_value(customer.address_line1)
          expect(subject).to contains_xml_node("#{xpath}/cbc:AdditionalStreetName").with_value(customer.address_line2)
        end

        it "expects to have city" do
          expect(subject).to contains_xml_node("#{xpath}/cbc:CityName").with_value(customer.city)
        end

        it "expects to have zipcode" do
          expect(subject).to contains_xml_node("#{xpath}/cbc:PostalZone").with_value(customer.zipcode)
        end

        it "expects to have country" do
          expect(subject).to contains_xml_node("#{xpath}/cac:Country/cbc:IdentificationCode")
            .with_value(customer.country)
        end
      end

      context "with PartyLegalEntity" do
        let(:xpath) { "#{root}/cac:PartyLegalEntity" }

        it "expects to have registration name" do
          expect(subject).to contains_xml_node("#{xpath}/cbc:RegistrationName").with_value(customer.name)
        end
      end
    end
  end
end
