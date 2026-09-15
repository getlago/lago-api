# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::CancelAbandonedJob do
  subject(:job) { described_class }

  let(:payment) { create(:payment) }

  before { allow(Invoices::Payments::CancelAbandonedService).to receive(:call!) }

  it "forwards the payment to the service" do
    job.perform_now(payment)

    expect(Invoices::Payments::CancelAbandonedService).to have_received(:call!).with(payment:)
  end
end
