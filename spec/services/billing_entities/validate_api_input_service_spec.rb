# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::ValidateApiInputService do
  subject(:result) { described_class.call(organization:, params:, require_code:) }

  let_it_be(:organization) { create_default(:organization) }
  let(:params) { {} }
  let(:require_code) { false }

  it "accepts omitted settings" do
    expect(result).to be_success
  end

  context "when creating an entity" do
    let(:require_code) { true }
    let(:params) { {code: "entity.eu"} }

    it "accepts a nonblank code" do
      expect(result).to be_success
    end

    [nil, "", " "].each do |code|
      context "with a blank code #{code.inspect}" do
        let(:params) { {code:} }

        it "returns a validation error" do
          expect(result).to be_failure
          expect(result.error.messages).to eq(code: ["value_is_mandatory"])
        end
      end
    end

    context "without a code" do
      let(:params) { {} }

      it "returns a validation error" do
        expect(result).to be_failure
        expect(result.error.messages).to eq(code: ["value_is_mandatory"])
      end
    end
  end

  context "with tax codes" do
    let(:params) { {tax_codes: ["vat"]} }

    it "accepts strings" do
      expect(result).to be_success
    end

    context "with an empty list" do
      let(:params) { {tax_codes: []} }

      it "allows removing the tax assignments" do
        expect(result).to be_success
      end
    end

    [123, nil, false].each do |code|
      context "with a non-string code #{code.inspect}" do
        let(:params) { {tax_codes: ["vat", code]} }

        it "returns a validation error" do
          expect(result).to be_failure
          expect(result.error.messages).to eq(tax_codes: ["value_is_invalid"])
        end
      end
    end
  end

  %i[eu_tax_management einvoicing finalize_zero_amount_invoice].each do |field|
    [true, false, "true", "false"].each do |value|
      context "with #{field} set to #{value}" do
        let(:params) { {field => value} }

        it "accepts the boolean" do
          expect(result).to be_success
        end
      end
    end

    [nil, "", "banana", 1].each do |value|
      context "with invalid #{field} #{value.inspect}" do
        let(:params) { {field => value} }

        it "returns a validation error" do
          expect(result).to be_failure
          expect(result.error.messages).to eq(field => ["value_is_invalid"])
        end
      end
    end
  end

  context "with invoice custom section codes" do
    let(:section) { create(:invoice_custom_section, organization:) }
    let(:params) { {invoice_custom_section_codes: [section.code]} }

    it "accepts the organization's code" do
      expect(result).to be_success
    end

    context "with duplicate codes" do
      let(:params) { {invoice_custom_section_codes: [section.code, section.code]} }

      it "accepts the duplicates" do
        expect(result).to be_success
      end
    end

    context "with an empty list" do
      let(:params) { {invoice_custom_section_codes: []} }

      it "allows clearing the sections" do
        expect(result).to be_success
      end
    end

    context "with an unknown code" do
      let(:params) { {invoice_custom_section_codes: [section.code, "unknown"]} }

      it "returns not found" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("invoice_custom_section_not_found")
      end
    end

    context "with a foreign code" do
      let(:section) { create(:invoice_custom_section, organization: create(:organization)) }

      it "returns not found" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("invoice_custom_section_not_found")
      end
    end

    [123, nil, false].each do |code|
      context "with a non-string code #{code.inspect}" do
        let(:params) { {invoice_custom_section_codes: [code]} }

        it "returns a validation error" do
          expect(result).to be_failure
          expect(result.error.messages).to eq(invoice_custom_section_codes: ["value_is_invalid"])
        end
      end
    end
  end

  {
    document_numbering: ["per_customer", :document_numbering],
    subscription_invoice_issuing_date_anchor: ["next_period_start", :periodic_invoice_issuing_date_anchor],
    subscription_invoice_issuing_date_adjustment: ["keep_anchor", :periodic_invoice_issuing_date_adjustment]
  }.each do |attribute, (valid_value, field)|
    context "with #{attribute}" do
      let(:params) { (attribute == :document_numbering) ? {attribute => value} : {billing_configuration: {attribute => value}} }
      let(:value) { valid_value }

      it "accepts a supported value" do
        expect(result).to be_success
      end

      ["invalid", nil, 123].each do |invalid_value|
        context "with #{invalid_value.inspect}" do
          let(:value) { invalid_value }

          it "returns a validation error with the values allowed" do
            expect(result).to be_failure
            expect(result.error.messages).to eq(field => ["value_is_invalid"])
            expect(result.error.meta).to eq(field => {allowed_values: described_class::ENUMS[attribute].last.values})
          end
        end
      end
    end
  end

  context "with an invalid enum and other invalid fields" do
    let(:params) { {document_numbering: "invalid", tax_codes: [1], logo: 123} }

    it "returns every error, in order, the values allowed on the enum only" do
      expect(result.error.messages).to eq(document_numbering: ["value_is_invalid"], tax_codes: ["value_is_invalid"], logo: ["value_is_invalid"])
      expect(result.error.messages.keys).to eq(%i[document_numbering tax_codes logo])
      expect(result.error.meta).to eq(document_numbering: {allowed_values: %w[per_customer per_billing_entity]})
    end
  end

  [123, "not-a-data-url", "data:image/png;base64,"].each do |logo|
    context "with invalid logo #{logo.inspect}" do
      let(:params) { {logo:} }

      it "returns a validation error" do
        expect(result).to be_failure
        expect(result.error.messages).to eq(logo: ["value_is_invalid"])
      end
    end
  end

  context "when clearing a logo" do
    let(:params) { {logo: nil} }

    it "allows removal" do
      expect(result).to be_success
    end
  end
end
