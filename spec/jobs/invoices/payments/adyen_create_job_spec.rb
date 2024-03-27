# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::AdyenCreateJob, type: :job do
  let(:invoice) { create(:invoice) }

  let(:adyen_service) { instance_double(Invoices::Payments::AdyenService) }

  it "calls the stripe create service" do
    allow(Invoices::Payments::AdyenService).to receive(:new)
      .with(invoice)
      .and_return(adyen_service)
    allow(adyen_service).to receive(:create)
      .and_return(BaseService::Result.new)

    described_class.perform_now(invoice)

    expect(Invoices::Payments::AdyenService).to have_received(:new)
    expect(adyen_service).to have_received(:create)
  end
end
