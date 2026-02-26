# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ActivationRules::ProcessPaymentJob do
  let(:invoice) { create(:invoice) }
  let(:payment_status) { :succeeded }

  describe "#perform" do
    before do
      allow(Subscriptions::ActivationRules::ProcessPaymentService).to receive(:call!)
        .and_return(BaseService::Result.new)
    end

    it "calls the ProcessPaymentService" do
      described_class.perform_now(invoice, payment_status)

      expect(Subscriptions::ActivationRules::ProcessPaymentService).to have_received(:call!)
        .with(invoice:, payment_status:)
    end
  end
end
