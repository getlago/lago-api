# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::DestroyJob, type: :job do
  let(:charge) { create(:charge) }

  before do
    allow(Charges::DestroyService).to receive(:call).with(charge:).and_return(BaseService::Result.new)
  end

  it 'calls the service' do
    described_class.perform_now(plan:, params:)

    expect(Charges::DestroyService).to have_received(:call)
  end
end
