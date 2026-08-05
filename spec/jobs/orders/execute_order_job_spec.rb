# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::ExecuteOrderJob, job: true do
  let(:order) { create(:order) }

  it "calls ExecuteService" do
    allow(Orders::ExecuteService).to receive(:call!)

    described_class.perform_now(order)

    expect(Orders::ExecuteService).to have_received(:call!).with(order:)
  end
end
