# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::UpdatePaymentMethodDataJob, type: :job do
  let(:provider_payment_id) { "pi_123" }
  let(:provider_payment_method_id) { "pm_001" }

  it "calls the service" do
    create(:payment, provider_payment_id:)

    allow(Payments::UpdatePaymentMethodDataService)
      .to receive(:call!).with(payment: Payment, provider_payment_method_id:).and_return(BaseService::Result.new)

    described_class.perform_now(provider_payment_id: "pi_123", provider_payment_method_id:)

    expect(Payments::UpdatePaymentMethodDataService).to have_received(:call!)
  end

  context "when payment is not found" do
    it "does not call the service" do
      allow(Payments::UpdatePaymentMethodDataService).to receive(:call!)

      expect {
        described_class.perform_now(provider_payment_id: "pi_123", provider_payment_method_id:)
      }.to raise_error(ActiveRecord::RecordNotFound)

      expect(Payments::UpdatePaymentMethodDataService).not_to have_received(:call!)
    end
  end
end
