# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReceipts::GeneratePdfJob, type: :job do
  let(:payment_receipt) { create(:payment_receipt) }
  let(:result) { BaseService::Result.new }
  let(:generate_service) { instance_double(PaymentReceipts::GeneratePdfService) }

  it "delegates to the Generate service" do
    allow(PaymentReceipts::GeneratePdfService).to receive(:new)
      .with(payment_receipt:, context: "api")
      .and_return(generate_service)
    allow(generate_service).to receive(:call_with_activity_log)
      .and_return(result)

    described_class.perform_now(payment_receipt)

    expect(PaymentReceipts::GeneratePdfService).to have_received(:new)
    expect(generate_service).to have_received(:call_with_activity_log)
  end
end
