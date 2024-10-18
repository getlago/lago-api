# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::DestroyJob, type: :job do
  let(:charge) { create(:standard_charge) }

  before do
    allow(Charges::DestroyService).to receive(:call).with(charge:).and_return(BaseService::Result.new)
  end

  it 'calls the service' do
    described_class.perform_now(charge:)

    expect(Charges::DestroyService).to have_received(:call)
  end
end
