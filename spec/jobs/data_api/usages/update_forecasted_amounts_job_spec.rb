# frozen_string_literal: true

RSpec.describe DataApi::Usages::UpdateForecastedAmountsJob, type: :job do
  it "is enqueued on the low_priority queue" do
    expect(described_class.queue_name).to eq("low_priority")
  end

  describe "#perform" do
    let(:usage_amounts) { [10, 20, 30] }

    before do
      allow(DataApi::Usages::UpdateForecastedAmountsService).to receive(:call!).with(usage_amounts:)
    end

    it "calls UpdateForecastedAmountsService with the provided usage amounts" do
      described_class.perform_now(usage_amounts)

      expect(DataApi::Usages::UpdateForecastedAmountsService).to have_received(:call!).with(usage_amounts:)
    end
  end
end
