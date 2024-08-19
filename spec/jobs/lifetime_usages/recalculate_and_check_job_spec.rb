# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifetimeUsages::RecalculateAndCheckJob, type: :job do
  let(:lifetime_usage) { create(:lifetime_usage) }

  it 'delegates to the RecalculateAndCheck service' do
    allow(LifetimeUsages::RecalculateAndCheckService).to receive(:call)
    described_class.perform_now(lifetime_usage)
    expect(LifetimeUsages::RecalculateAndCheckService).to have_received(:call).with(lifetime_usage:)
  end
end
