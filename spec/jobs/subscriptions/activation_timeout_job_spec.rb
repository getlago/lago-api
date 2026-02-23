# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationTimeoutJob, type: :job do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, :activating, customer:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  let(:activation_failed_result) { BaseService::Result.new }

  before do
    create(:invoice_subscription, invoice:, subscription:)
    allow(Subscriptions::ActivationFailedService).to receive(:call!).and_return(activation_failed_result)
  end

  context "when subscription is still activating" do
    it "calls ActivationFailedService" do
      described_class.perform_now(subscription)

      expect(Subscriptions::ActivationFailedService).to have_received(:call!).with(
        subscription:,
        invoice:
      )
    end
  end

  context "when subscription is already active" do
    let(:subscription) { create(:subscription, :active, customer:) }

    it "does not call ActivationFailedService" do
      described_class.perform_now(subscription)

      expect(Subscriptions::ActivationFailedService).not_to have_received(:call!)
    end
  end

  context "when subscription is already terminated" do
    let(:subscription) { create(:subscription, :terminated, customer:) }

    it "does not call ActivationFailedService" do
      described_class.perform_now(subscription)

      expect(Subscriptions::ActivationFailedService).not_to have_received(:call!)
    end
  end
end
