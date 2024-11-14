# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::GocardlessCreateJob, type: :job do
  let(:invoice) { create(:invoice) }

  it 'calls the stripe create service' do
    allow(Invoices::Payments::GocardlessService).to receive(:call)
      .with(invoice)
      .and_return(BaseService::Result.new)

    described_class.perform_now(invoice)

    expect(Invoices::Payments::GocardlessService).to have_received(:call)
  end
end
