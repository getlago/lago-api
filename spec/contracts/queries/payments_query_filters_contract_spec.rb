# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::PaymentsQueryFiltersContract do
  subject(:result) { described_class.new.call(filters.to_h) }

  let(:filters) { {} }

  context "when filters are valid" do
    context "when invoice_id is valid" do
      let(:filters) { {invoice_id: "7b199d93-2663-4e68-beca-203aefcd019b"} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end

    context "when invoice_id is blank" do
      let(:filters) { {invoice_id: nil} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end

    context "when external_customer_id is valid" do
      let(:filters) { {external_customer_id: "valid_string"} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end

    context "when external_customer_id is blank" do
      let(:filters) { {external_customer_id: nil} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end

    context "when both invoice_id and external_customer_id are valid" do
      let(:filters) { {invoice_id: "7b199d93-2663-4e68-beca-203aefcd019b", external_customer_id: "valid_string"} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end
  end

  context "when filters are invalid" do
    context "when invoice_id is not a UUID" do
      let(:filters) { {invoice_id: "invalid_uuid"} }

      it "is invalid" do
        expect(result.success?).to be(false)
        expect(result.errors.to_h).to include(invoice_id: ["is in invalid format"])
      end
    end

    context "when external_customer_id is not a string" do
      let(:filters) { {external_customer_id: 123} }

      it "is invalid" do
        expect(result.success?).to be(false)
        expect(result.errors.to_h).to include(external_customer_id: ["must be a string"])
      end
    end

    context "when both invoice_id and external_customer_id are invalid" do
      let(:filters) { {invoice_id: "invalid_uuid", external_customer_id: 123} }

      it "is invalid" do
        expect(result.success?).to be(false)
        expect(result.errors.to_h).to include(
          invoice_id: ["is in invalid format"],
          external_customer_id: ["must be a string"]
        )
      end
    end
  end

  it "accepts no filters" do
    expect(result).to be_success
  end

  {
    payment_status: Payment::PAYABLE_PAYMENT_STATUS,
    payment_provider_type: Customer::PAYMENT_PROVIDERS,
    payment_method_type: PaymentMethod::PROVIDER_METHOD_TYPES,
    payment_type: Payment::PAYMENT_TYPES.keys.map(&:to_s),
    payable_type: Payment::PAYABLE_TYPES
  }.each do |field, values|
    context "with #{field}" do
      [values, *values, [], nil].each do |value|
        it "accepts #{value.inspect}" do
          expect(described_class.new.call(field => value)).to be_success
        end
      end

      ["unknown", [values.first, "unknown"], {foo: "bar"}, 123].each do |value|
        it "rejects #{value.inspect}" do
          validation = described_class.new.call(field => value)
          expect(validation).not_to be_success
          expect(validation.errors.to_h).to have_key(field)
        end
      end
    end
  end

  %i[amount_from amount_to].each do |field|
    [0, "0", "5000000000", "9007199254740993", 9_223_372_036_854_775_807, nil].each do |amount|
      it "accepts #{field}=#{amount.inspect}" do
        expect(described_class.new.call(field => amount)).to be_success
      end
    end

    [-1, "-1", "1.5", "invalid", 9_223_372_036_854_775_808].each do |amount|
      it "rejects #{field}=#{amount.inspect}" do
        validation = described_class.new.call(field => amount)
        expect(validation).not_to be_success
        expect(validation.errors.to_h).to have_key(field)
      end
    end
  end

  it "accepts equal bounds" do
    expect(described_class.new.call(amount_from: "9007199254740993", amount_to: "9007199254740993")).to be_success
  end

  it "rejects reversed bounds after coercing integers" do
    validation = described_class.new.call(amount_from: "500", amount_to: "100")
    expect(validation.errors.to_h).to eq(amount_to: ["must be greater than or equal to amount_from"])
  end

  %i[receipt_number invoice_number].each do |field|
    it "accepts #{field} up to 255 characters" do
      expect(described_class.new.call(field => "a" * 255)).to be_success
    end

    it "rejects longer #{field}" do
      expect(described_class.new.call(field => "a" * 256).errors.to_h).to have_key(field)
    end
  end

  it "accepts a supported currency" do
    expect(described_class.new.call(currency: "EUR")).to be_success
  end

  it "rejects an unsupported currency" do
    expect(described_class.new.call(currency: "XYZ").errors.to_h).to have_key(:currency)
  end
end
