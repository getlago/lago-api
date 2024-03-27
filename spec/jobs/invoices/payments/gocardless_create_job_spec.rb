# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::GocardlessCreateJob, type: :job do
  let(:invoice) { create(:invoice) }

  let(:gocardless_service) { instance_double(Invoices::Payments::GocardlessService) }

  it "calls the stripe create service" do
    allow(Invoices::Payments::GocardlessService).to receive(:new)
      .with(invoice)
      .and_return(gocardless_service)
    allow(gocardless_service).to receive(:create)
      .and_return(BaseService::Result.new)

    described_class.perform_now(invoice)

    expect(Invoices::Payments::GocardlessService).to have_received(:new)
    expect(gocardless_service).to have_received(:create)
  end
end
