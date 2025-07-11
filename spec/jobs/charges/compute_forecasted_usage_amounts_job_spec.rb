# frozen_string_literal: true

RSpec.describe Charges::ComputeForecastedUsageAmountsJob, type: :job do
  it "is enqueued on the low_priority queue" do
    expect(described_class.queue_name).to eq("low_priority")
  end

  describe "#perform" do
    let(:organization) { instance_double("Organization") }

    before do
      allow(Charges::ComputeForecastedUsageAmountsService).to receive(:call!).with(organization:)
    end

    it "calls the service with the correct arguments" do
      described_class.perform_now(organization: organization)

      expect(Charges::ComputeForecastedUsageAmountsService).to have_received(:call!).with(organization:)
    end
  end
end
