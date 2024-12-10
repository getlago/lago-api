# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::CreateJob, type: :job do
  let(:invoice) { create(:invoice) }
  let(:payment_provider) { 'stripe' }

  it 'calls the stripe create service' do
    allow(Invoices::Payments::CreateService).to receive(:call!)
      .with(invoice:, payment_provider:)
      .and_return(BaseService::Result.new)

    described_class.perform_now(invoice:, payment_provider:)

    expect(Invoices::Payments::CreateService).to have_received(:call!)
  end
end
