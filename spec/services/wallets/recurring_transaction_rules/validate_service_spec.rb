# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::RecurringTransactionRules::ValidateService do
  subject(:validate_service) { described_class.new(params:) }

  let(:params) do
    {
      trigger: "interval",
      interval: "weekly"
    }
  end

  describe "#call" do
    it "returns true" do
      expect(validate_service.call).to be_truthy
    end

    context "when invalid interval" do
      let(:params) do
        {
          trigger: "interval",
          interval: "invalid"
        }
      end

      it "returns false" do
        expect(validate_service.call).to be_falsey
      end
    end

    context "when invalid threshold" do
      let(:params) do
        {
          trigger: "threshold",
          threshold_credits: "invalid"
        }
      end

      it "returns false" do
        expect(validate_service.call).to be_falsey
      end
    end

    context "when invalid method" do
      let(:params) do
        {
          method: "target",
          trigger: "interval",
          interval: "weekly",
          target_ongoing_balance: "invalid"
        }
      end

      it "returns false" do
        expect(validate_service.call).to be_falsey
      end
    end

    context "when valid transaction_metadata" do
      let(:params) do
        {
          trigger: "interval",
          interval: "weekly",
          transaction_metadata: [{"key" => "valid_key", "value" => "invalid_value"}]
        }
      end

      it "returns true" do
        expect(validate_service.call).to eq true
      end
    end

    context "when invalid transaction_metadata" do
      let(:params) do
        {
          trigger: "interval",
          interval: "weekly",
          transaction_metadata: {"key" => "valid_key", "value" => "invalid_value"}
        }
      end

      it "returns false" do
        expect(validate_service.call).to eq false
      end
    end

    context "when invalid credits" do
      let(:params) do
        {
          trigger: "interval",
          interval: "weekly",
          paid_credits: "invalid"
        }
      end

      it "returns false" do
        expect(validate_service.call).to be_falsey
      end
    end

    describe "#valid_expiration_at?" do
      context "when expiration_at is blank" do
        let(:params) do
          {
            trigger: "interval",
            interval: "weekly",
            expiration_at: nil
          }
        end

        it "returns true" do
          expect(validate_service.call).to eq true
        end
      end

      context "when expiration_at is an invalid format" do
        let(:params) do
          {
            trigger: "interval",
            interval: "weekly",
            expiration_at: "invalid-date"
          }
        end

        it "returns false" do
          expect(validate_service.call).to be_falsey
        end
      end

      context "when expiration_at is a past date" do
        let(:params) do
          {
            trigger: "interval",
            interval: "weekly",
            expiration_at: (Time.current - 1.hour).iso8601
          }
        end

        it "returns false" do
          expect(validate_service.call).to be_falsey
        end
      end

      context "when expiration_at is a valid future date" do
        let(:params) do
          {
            trigger: "interval",
            interval: "weekly",
            expiration_at: (Time.current + 1.hour).iso8601
          }
        end

        it "returns true" do
          expect(validate_service.call).to eq true
        end
      end
    end
  end
end
