# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::StripeCreateJob, type: :job do
  let(:invoice) { create(:invoice) }

  it 'calls the stripe create service' do
    allow(Invoices::Payments::CreateService).to receive(:call!)
      .with(invoice:, payment_provider: :stripe)
      .and_return(BaseService::Result.new)

    described_class.perform_now(invoice)

    expect(Invoices::Payments::CreateService).to have_received(:call!)
  end
end
