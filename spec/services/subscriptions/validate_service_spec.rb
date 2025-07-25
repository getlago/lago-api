# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ValidateService, type: :service do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseService::Result.new }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription_at) { Time.current.iso8601 }
  let(:ending_at) { (Time.current + 1.year).iso8601 }

  let(:args) do
    {
      customer:,
      plan:,
      subscription_at:,
      ending_at:,
      on_termination_credit_note:,
      on_termination_invoice:
    }
  end

  let(:on_termination_credit_note) { nil }
  let(:on_termination_invoice) { nil }

  describe "#ending_at" do
    subject(:method_call) { validate_service.__send__(:ending_at) }

    context "when date contains milliseconds" do
      let(:ending_at) { "2020-01-01T00:00:00.000Z" }

      it "returns the date" do
        expect(subject).to eq(DateTime.strptime(ending_at, "%Y-%m-%dT%H:%M:%S.%LZ"))
      end
    end

    context "when date does not contain milliseconds" do
      let(:ending_at) { "2020-01-01T00:00:00Z" }

      it "returns the date" do
        expect(subject).to eq(DateTime.strptime(ending_at))
      end
    end
  end

  describe "#subscription_at" do
    subject(:method_call) { validate_service.__send__(:subscription_at) }

    context "when date contains milliseconds" do
      let(:subscription_at) { "2021-02-01T00:00:00.00Z" }

      it "returns the date" do
        expect(subject).to eq(DateTime.strptime(subscription_at, "%Y-%m-%dT%H:%M:%S.%LZ"))
      end
    end

    context "when date does not contain milliseconds" do
      let(:subscription_at) { "2020-01-01T00:00:00Z" }

      it "returns the date" do
        expect(subject).to eq(DateTime.strptime(subscription_at))
      end
    end
  end

  describe ".valid?" do
    it "returns true" do
      expect(validate_service).to be_valid
    end

    context "when customer does not exist" do
      let(:customer) { nil }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid

        aggregate_failures do
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq("customer_not_found")
        end
      end
    end

    context "when plan does not exist" do
      let(:plan) { nil }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid

        aggregate_failures do
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq("plan_not_found")
        end
      end
    end

    context "with invalid subscription_at" do
      context "when string cannot be parsed to date" do
        let(:subscription_at) { "invalid" }

        it "returns false and result has errors" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:subscription_at]).to eq(["invalid_date"])
        end
      end

      context "when subscription_at is integer" do
        let(:subscription_at) { 123 }

        it "returns false and result has errors" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:subscription_at]).to eq(["invalid_date"])
        end
      end
    end

    context "with invalid ending_at" do
      context "when string cannot be parsed to date" do
        let(:ending_at) { "invalid" }

        it "returns false and result has errors" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:ending_at]).to eq(["invalid_date"])
        end
      end

      context "when ending_at is integer" do
        let(:ending_at) { 123 }

        it "returns false and result has errors" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:ending_at]).to eq(["invalid_date"])
        end
      end

      context "when ending_at is less than subscription_at and current time" do
        let(:ending_at) { (Time.current - 1.year).iso8601 }

        it "returns false and result has errors" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:ending_at]).to eq(["invalid_date"])
        end
      end
    end

    context "with invalid on_termination_credit_note" do
      let(:on_termination_credit_note) { "invalid" }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:on_termination_credit_note]).to eq(["invalid_value"])
      end
    end

    context "with valid on_termination_credit_note" do
      let(:on_termination_credit_note) { "credit" }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "with invalid on_termination_invoice" do
      let(:on_termination_invoice) { "invalid" }

      it "returns false and result has errors" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:on_termination_invoice]).to eq(["invalid_value"])
      end
    end

    context "with valid on_termination_invoice" do
      let(:on_termination_invoice) { "generate" }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "with valid on_termination_invoice skip" do
      let(:on_termination_invoice) { "skip" }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end
  end
end
