# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::UpdatePaymentMethodDataJob, type: :job do
  let(:payment) { create(:payment) }
  let(:provider_payment_method_id) { "pm_001" }

  it "calls the service" do
    allow(Payments::UpdatePaymentMethodDataService)
      .to receive(:call!).with(payment:, provider_payment_method_id:).and_return(BaseService::Result.new)

    described_class.perform_now(payment:, provider_payment_method_id:)

    expect(Payments::UpdatePaymentMethodDataService).to have_received(:call!)
  end
end
