# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CreatePayInAdvanceFixedChargesJob do
  subject(:perform_now) { described_class.perform_now(subscription, timestamp) }

  let(:subscription) { create(:subscription) }
  let(:timestamp) { Time.current.to_i }

  before do
    allow(Invoices::CreatePayInAdvanceFixedChargesService).to receive(:call!)
      .with(subscription:, timestamp:)
  end

  it "calls the create pay in advance fixed charges service" do
    perform_now

    expect(Invoices::CreatePayInAdvanceFixedChargesService).to have_received(:call!)
  end
end
