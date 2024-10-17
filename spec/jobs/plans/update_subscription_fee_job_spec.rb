# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::UpdateSubscriptionFeeJob, type: :job do
  let(:plan) { create(:plan) }
  let(:amount_cents) { 200 }

  before do
    allow(Plans::UpdateSubscriptionFeeService).to receive(:call).with(plan:, amount_cents:)
  end

  it 'calls the service' do
    described_class.perform_now(plan:, amount_cents:)

    expect(Plans::UpdateSubscriptionFeeService).to have_received(:call)
  end
end
