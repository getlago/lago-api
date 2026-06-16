# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::ComputeMentionVariablesService do
  subject(:service) { described_class.new(quote_version:) }

  let(:organization) { create(:organization, name: "Lago") }
  let(:billing_entity) do
    create(
      :billing_entity,
      organization:,
      name: "Mistral AI SAS",
      legal_name: "Mistral AI SAS",
      tax_identification_number: "FR12345678901",
      email: "billing@mistral.ai",
      address_line1: "4 rue de la Paix",
      address_line2: nil,
      zipcode: "75002",
      city: "Paris",
      state: nil,
      country: "FR",
      net_payment_term: 30
    )
  end
  let(:customer_net_payment_term) { nil }
  let(:customer_document_locale) { nil }
  let(:customer) do
    create(
      :customer,
      organization:,
      billing_entity:,
      name: "Mistral AI",
      email: "procurement@mistral.ai",
      net_payment_term: customer_net_payment_term,
      document_locale: customer_document_locale
    )
  end
  let(:quote) { create(:quote, organization:, customer:) }
  let(:start_date) { Date.new(2026, 4, 1) }
  let(:end_date) { Date.new(2027, 4, 1) }
  let(:quote_version) do
    create(:quote_version, quote:, organization:, currency: "EUR", start_date:, end_date:)
  end

  describe ".call" do
    let(:result) { service.call }
    let(:variables) { result.mention_variables }

    it "computes the full mention variables dictionary" do
      expect(result).to be_success
      expect(variables).to include(
        "customer_name" => "Mistral AI",
        "customer_email" => "procurement@mistral.ai",
        "organization_name" => "Lago",
        "organization_logo" => organization.logo_url,
        "billing_entity_name" => "Mistral AI SAS",
        "billing_entity_legal_name" => "Mistral AI SAS",
        "billing_entity_address" => "4 rue de la Paix\n75002 Paris\nFrance",
        "billing_entity_tax_id" => "FR12345678901",
        "billing_entity_email" => "billing@mistral.ai",
        "quote_number" => quote.number,
        "quote_version" => quote_version.version.to_s,
        "quote_currency" => "EUR",
        "commercial_terms_term_duration" => "1 year",
        "commercial_terms_start_date" => "Apr 01, 2026",
        "commercial_terms_payment_terms" => "Net 30"
      )
      expect(variables["quote_date"]).to be_present
    end

    context "when the customer overrides the net payment term" do
      let(:customer_net_payment_term) { 45 }

      it "uses the customer's payment term" do
        expect(variables["commercial_terms_payment_terms"]).to eq("Net 45")
      end
    end

    context "when the customer document locale is French" do
      let(:customer_document_locale) { "fr" }

      it "localizes the dates, duration, payment terms and address" do
        expect(variables).to include(
          "commercial_terms_term_duration" => "un an",
          "commercial_terms_start_date" => "1 avr. 2026",
          "commercial_terms_payment_terms" => "Net 30",
          "billing_entity_address" => "4 rue de la Paix\n75002 Paris\nFrance"
        )
      end
    end

    context "when the term spans whole months" do
      let(:start_date) { Date.new(2026, 1, 1) }
      let(:end_date) { Date.new(2026, 4, 1) }

      it "renders the duration in months" do
        expect(variables["commercial_terms_term_duration"]).to eq("3 months")
      end
    end

    context "when the term spans less than a month" do
      let(:start_date) { Date.new(2026, 1, 1) }
      let(:end_date) { Date.new(2026, 1, 15) }

      it "renders the duration in days" do
        expect(variables["commercial_terms_term_duration"]).to eq("14 days")
      end
    end

    context "when the end date is missing" do
      let(:end_date) { nil }

      it "leaves the term duration blank" do
        expect(variables["commercial_terms_term_duration"]).to be_nil
      end
    end

    context "when the term ends on a shorter month-end" do
      let(:start_date) { Date.new(2026, 1, 31) }
      let(:end_date) { Date.new(2026, 2, 28) }

      it "rounds down to whole days rather than a month" do
        expect(variables["commercial_terms_term_duration"]).to eq("28 days")
      end
    end

    context "when the term spans more than a year but not a whole multiple" do
      let(:start_date) { Date.new(2026, 1, 1) }
      let(:end_date) { Date.new(2027, 2, 1) }

      it "renders the total months rather than years plus months" do
        expect(variables["commercial_terms_term_duration"]).to eq("13 months")
      end
    end
  end
end
