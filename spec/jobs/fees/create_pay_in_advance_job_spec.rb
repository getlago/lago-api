# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::CreatePayInAdvanceJob do
  let(:charge) { create(:standard_charge, :pay_in_advance) }
  let(:event) { create(:event) }

  let(:result) { BaseService::Result.new }

  it "delegates to the pay_in_advance aggregation service" do
    allow(Fees::CreatePayInAdvanceService).to receive(:call)
      .with(charge:, event:, billing_at: nil)
      .and_return(result)

    described_class.perform_now(charge:, event:)

    expect(Fees::CreatePayInAdvanceService).to have_received(:call)
  end
end
