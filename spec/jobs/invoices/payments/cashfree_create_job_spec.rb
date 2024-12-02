# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::CashfreeCreateJob, type: :job do
  let(:invoice) { create(:invoice) }

  it "calls the stripe create service" do
    allow(Invoices::Payments::CashfreeService).to receive(:call!)
      .with(invoice)
      .and_return(BaseService::Result.new)

    described_class.perform_now(invoice)

    expect(Invoices::Payments::CashfreeService).to have_received(:call!)
  end
end
