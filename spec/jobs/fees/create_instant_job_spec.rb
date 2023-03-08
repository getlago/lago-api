# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::CreateInstantJob, type: :job do
  let(:charge) { create(:standard_charge, :instant) }
  let(:event) { create(:event) }

  let(:result) { BaseService::Result.new }

  let(:instant_service) do
    instance_double(Fees::CreateInstantService)
  end

  it 'delegates to the instant aggregation service' do
    allow(Fees::CreateInstantService).to receive(:new)
      .with(charge:, event:)
      .and_return(instant_service)
    allow(instant_service).to receive(:call)
      .and_return(result)

    described_class.perform_now(charge:, event:)

    expect(Fees::CreateInstantService).to have_received(:new)
    expect(instant_service).to have_received(:call)
  end
end
