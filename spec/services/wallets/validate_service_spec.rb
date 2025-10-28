# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::ValidateService do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseService::Result.new }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:customer_id) { customer.external_id }
  let(:paid_credits) { "1.00" }
  let(:granted_credits) { "0.00" }
  let(:expiration_at) { (Time.current + 1.year).iso8601 }
  let(:args) do
    {
      customer:,
      organization_id: organization.id,
      paid_credits:,
      granted_credits:,
      expiration_at:
    }
  end

  before { subscription }

  describe ".valid?" do
    it "returns true" do
      expect(validate_service).to be_valid
    end

    context "when customer does not exist" do
      let(:args) do
        {
          customer: nil,
          organization_id: organization.id,
          paid_credits:,
          granted_credits:
        }
      end

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:customer]).to eq(["customer_not_found"])
      end
    end

    # uncomment when we support multiple wallets per customer
    # context "when customer already has a wallet" do
    #   before { create(:wallet, customer:) }
    #
    #   it "returns true without errors" do
    #     expect(validate_service).to be_valid
    #   end
    # end

    context "with invalid paid_credits" do
      let(:paid_credits) { "foobar" }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:paid_credits]).to eq(["invalid_paid_credits", "invalid_amount"])
      end
    end

    context "with invalid granted_credits" do
      let(:granted_credits) { "foobar" }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:granted_credits]).to eq(["invalid_granted_credits", "invalid_amount"])
      end
    end

    context "with invalid expiration_at" do
      context "when string cannot be parsed to date" do
        let(:expiration_at) { "invalid" }

        it "returns false and result has errors" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:expiration_at]).to eq(["invalid_date"])
        end
      end

      context "when expiration_at is an integer" do
        let(:expiration_at) { 123 }

        it "returns false and result has errors" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:expiration_at]).to eq(["invalid_date"])
        end
      end

      context "when expiration_at is in the past" do
        let(:expiration_at) { (Time.current - 1.hour).iso8601 }

        it "returns false and result has errors" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:expiration_at]).to eq(["invalid_date"])
        end
      end

      context "when expiration_at is a valid datetime string but in the future" do
        let(:expiration_at) { (Time.current + 1.hour).iso8601 }

        it "returns true and has no errors" do
          expect(validate_service).to be_valid
        end
      end
    end

    context "with invalid transaction metadata" do
      let(:args) do
        {
          customer:,
          organization_id: organization.id,
          paid_credits:,
          granted_credits:,
          expiration_at:,
          transaction_metadata: [{key: "valid key", value1: "invalid value"}]
        }
      end

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:metadata]).to eq(["invalid_key_value_pair"])
      end
    end

    context "with recurring transaction rules" do
      let(:rules) do
        [
          {
            trigger: "interval",
            interval: "monthly"
          },
          {
            trigger: "threshold",
            threshold_credits: "-1.0"
          }
        ]
      end
      let(:args) do
        {
          customer:,
          organization_id: organization.id,
          paid_credits:,
          granted_credits:,
          recurring_transaction_rules: rules
        }
      end

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:recurring_transaction_rules]).to eq(["invalid_number_of_recurring_rules"])
      end
    end

    context "with limitations" do
      let(:limitations) do
        {
          fee_types: %w[invalid charge]
        }
      end
      let(:args) do
        {
          customer:,
          organization_id: organization.id,
          paid_credits:,
          granted_credits:,
          applies_to: limitations
        }
      end

      it "returns false and result has errors if fee type is invalid" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:applies_to]).to eq(["invalid_limitations"])
      end

      context "with billable metric limitations" do
        let(:billable_metric) { create(:billable_metric, organization:) }
        let(:billable_metric_identifiers) { [billable_metric.id, "invalid"] }
        let(:limitations) do
          {
            billable_metric_ids: billable_metric_identifiers
          }
        end

        before do
          result.billable_metrics = [billable_metric]
          result.billable_metric_identifiers = billable_metric_identifiers
        end

        it "returns false and result has errors if BM is invalid" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:applies_to]).to eq(["invalid_limitations"])
        end
      end

      context "when limitations are valid" do
        let(:limitations) do
          {
            fee_types: %w[charge]
          }
        end

        it "returns true and result has no errors" do
          expect(validate_service).to be_valid
          expect(result.error).to be_nil
        end
      end
    end
  end
end
