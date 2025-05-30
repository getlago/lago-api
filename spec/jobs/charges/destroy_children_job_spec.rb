# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::DestroyChildrenJob, type: :job do
  let(:charge) { create(:standard_charge) }

  before do
    allow(Charges::DestroyChildrenService).to receive(:call!).with(charge)
      .and_return(Charges::DestroyChildrenService::Result.new)
  end

  it "calls the service" do
    described_class.perform_now(charge.id)

    expect(Charges::DestroyChildrenService).to have_received(:call!)
  end
end
