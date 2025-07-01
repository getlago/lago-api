# frozen_string_literal: true

RSpec.describe Charges::ComputeForecastedUsageAmountsJob, type: :job do
  let(:organization) { instance_double("Organization") }

  describe "#perform" do
    it "calls the service with the correct arguments" do
      allow(Charges::ComputeForecastedUsageAmountsService).to receive(:call!)

      described_class.perform_now(organization: organization)

      expect(Charges::ComputeForecastedUsageAmountsService)
        .to have_received(:call!).with(organization: organization)
    end

    it "is enqueued on the low_priority queue" do
      expect(described_class.queue_name).to eq("low_priority")
    end
  end
end
