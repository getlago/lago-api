# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingObjectConnections::ValidateService do
  subject(:validator) { described_class.new(result, connections:) }

  let(:result) { BaseResult.new }

  describe "#valid?" do
    context "when connections is absent" do
      let(:connections) { nil }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when connections is empty" do
      let(:connections) { {} }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "with a code" do
      let(:connections) { {payment: {code: "stripe_us"}} }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "with each supported behavior" do
      %w[inherit skip].each do |behavior|
        context "when behavior is #{behavior}" do
          let(:connections) { {tax: {behavior:}} }

          it "is valid" do
            expect(validator).to be_valid
          end
        end
      end
    end

    context "with every category" do
      let(:connections) do
        {
          payment: {behavior: "skip"},
          tax: {behavior: "skip"},
          accounting: {code: "netsuite_main"},
          crm: {behavior: "inherit"}
        }
      end

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the category is unknown" do
      let(:connections) { {shipping: {behavior: "skip"}} }

      it "returns an invalid_connection_category error" do
        expect(validator).not_to be_valid
        expect(validator.error_codes).to include("invalid_connection_category")
      end
    end

    context "when the behavior is unknown" do
      let(:connections) { {payment: {behavior: "whatever"}} }

      it "returns an invalid_connection_behavior error" do
        expect(validator).not_to be_valid
        expect(validator.error_codes).to include("invalid_connection_behavior")
      end
    end

    context "when behavior is specific" do
      let(:connections) { {payment: {behavior: "specific"}} }

      it "is rejected, since specific is implied by supplying a code" do
        expect(validator).not_to be_valid
        expect(validator.error_codes).to include("invalid_connection_behavior")
      end
    end

    context "when both a code and a behavior are given" do
      let(:connections) { {payment: {code: "stripe_us", behavior: "skip"}} }

      it "returns an invalid_connection_choice error" do
        expect(validator).not_to be_valid
        expect(validator.error_codes).to include("invalid_connection_choice")
      end
    end

    context "when neither a code nor a behavior is given" do
      let(:connections) { {payment: {}} }

      it "returns an invalid_connection_choice error" do
        expect(validator).not_to be_valid
        expect(validator.error_codes).to include("invalid_connection_choice")
      end
    end

    context "when the choice is not an object" do
      let(:connections) { {payment: "stripe_us"} }

      it "returns an invalid_connection_choice error" do
        expect(validator).not_to be_valid
        expect(validator.error_codes).to include("invalid_connection_choice")
      end
    end

    context "when connections is not an object" do
      let(:connections) { ["payment"] }

      it "returns an invalid_connections error" do
        expect(validator).not_to be_valid
        expect(validator.error_codes).to eq(["invalid_connections"])
      end
    end
  end
end
