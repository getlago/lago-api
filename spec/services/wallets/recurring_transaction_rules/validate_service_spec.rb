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
  end
end
