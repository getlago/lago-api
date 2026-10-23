# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::ValidateApiInputService do
  subject(:result) { described_class.call(params:, require_code:) }

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

  [true, false].each do |eu_tax_management|
    context "with EU tax management set to #{eu_tax_management}" do
      let(:params) { {eu_tax_management:} }

      it "accepts the boolean" do
        expect(result).to be_success
      end
    end
  end

  context "with null EU tax management" do
    let(:params) { {eu_tax_management: nil} }

    it "returns a validation error" do
      expect(result).to be_failure
      expect(result.error.messages).to eq(eu_tax_management: ["value_is_invalid"])
    end
  end

  {
    document_numbering: "per_customer",
    subscription_invoice_issuing_date_anchor: "next_period_start",
    subscription_invoice_issuing_date_adjustment: "keep_anchor"
  }.each do |field, valid_value|
    context "with #{field}" do
      let(:params) { (field == :document_numbering) ? {field => value} : {billing_configuration: {field => value}} }
      let(:value) { valid_value }

      it "accepts a supported value" do
        expect(result).to be_success
      end

      ["invalid", nil, 123].each do |invalid_value|
        context "with #{invalid_value.inspect}" do
          let(:value) { invalid_value }

          it "returns a validation error" do
            expect(result).to be_failure
            expect(result.error.messages).to eq(field => ["value_is_invalid"])
          end
        end
      end
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
