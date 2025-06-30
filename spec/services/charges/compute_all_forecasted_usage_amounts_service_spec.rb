# frozen_string_literal: true

RSpec.describe Charges::ComputeAllForecastedUsageAmountsService, type: :service do
  subject(:service) { described_class.new }

  describe "#organizations" do
    subject(:method_call) { service.send(:organizations) }

    before do
      create(:organization, premium_integrations: %i[forecasted_usage])
      create(:organization)
    end

    it "returns organizations only with forecasted usage support" do
      expect(subject).to eq(Organization.with_forecasted_usage_support)
    end
  end

  describe "#call" do
    let(:org_with_forecasted_usage) { create(:organization, premium_integrations: %i[forecasted_usage]) }
    let(:org_without_forecasted_usage) { create(:organization) }

    before do
      org_with_forecasted_usage
      org_without_forecasted_usage
    end

    it "enqueues the job only for organizations with forecasted usage support" do
      service.call

      expect(Charges::ComputeForecastedUsageAmountsJob).to have_been_enqueued.with(org_with_forecasted_usage)
      expect(Charges::ComputeForecastedUsageAmountsJob).not_to have_been_enqueued.with(org_without_forecasted_usage)
    end
  end
end
