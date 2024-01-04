# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::PinetCreateJob, type: :job do
  let(:invoice) { create(:invoice) }

  let(:pinet_service) { instance_double(Invoices::Payments::PinetService) }

  it 'calls the stripe create service' do
    allow(Invoices::Payments::PinetService).to receive(:new)
                                                 .with(invoice)
                                                 .and_return(pinet_service)
    allow(pinet_service).to receive(:create)
                              .and_return(BaseService::Result.new)

    described_class.perform_now(invoice)

    expect(Invoices::Payments::PinetService).to have_received(:new)
    expect(pinet_service).to have_received(:create)
  end
end
