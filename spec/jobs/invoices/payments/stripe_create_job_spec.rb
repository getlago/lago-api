# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::StripeCreateJob, type: :job do
  let(:invoice) { create(:invoice) }

  let(:stripe_service) { instance_double(Invoices::Payments::StripeService) }

  it "calls the stripe create service" do
    allow(Invoices::Payments::StripeService).to receive(:new)
      .with(invoice)
      .and_return(stripe_service)
    allow(stripe_service).to receive(:create)
      .and_return(BaseService::Result.new)

    described_class.perform_now(invoice)

    expect(Invoices::Payments::StripeService).to have_received(:new)
    expect(stripe_service).to have_received(:create)
  end
end
