# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::ActivateJob do
  subject(:activate_job) { described_class }

  let(:contract) { create(:contract, :pending) }

  before { allow(Contracts::ActivateService).to receive(:call!) }

  it "activates the contract" do
    activate_job.perform_now(contract)

    expect(Contracts::ActivateService).to have_received(:call!).with(contract:)
  end
end
