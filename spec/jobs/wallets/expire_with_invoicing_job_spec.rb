# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::ExpireWithInvoicingJob do
  subject(:expire_with_invoicing_job) { described_class }

  let(:wallet) { create(:wallet) }

  before { allow(Wallets::ExpireWithInvoicingService).to receive(:call!) }

  it "expires the wallet" do
    expire_with_invoicing_job.perform_now(wallet)

    expect(Wallets::ExpireWithInvoicingService).to have_received(:call!).with(wallet:, retrying: false)
  end

  context "when the job is retried" do
    it "tells the service it is retrying" do
      job = expire_with_invoicing_job.new(wallet)
      job.executions = 1
      job.perform_now

      expect(Wallets::ExpireWithInvoicingService).to have_received(:call!).with(wallet:, retrying: true)
    end
  end
end
