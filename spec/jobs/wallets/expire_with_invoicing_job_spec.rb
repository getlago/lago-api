# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::ExpireWithInvoicingJob do
  subject(:expire_with_invoicing_job) { described_class }

  let(:wallet) { create(:wallet) }

  before { allow(Wallets::ExpireWithInvoicingService).to receive(:call!) }

  it "expires the wallet" do
    expire_with_invoicing_job.perform_now(wallet)

    expect(Wallets::ExpireWithInvoicingService).to have_received(:call!).with(wallet:)
  end
end
