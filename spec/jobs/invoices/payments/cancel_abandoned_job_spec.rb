# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::CancelAbandonedJob, job: true do
  let(:payment) { create(:payment) }

  before { allow(Invoices::Payments::CancelAbandonedService).to receive(:call!) }

  it "calls the cancellation service" do
    described_class.perform_now(payment)

    expect(Invoices::Payments::CancelAbandonedService).to have_received(:call!).with(payment:)
  end
end
