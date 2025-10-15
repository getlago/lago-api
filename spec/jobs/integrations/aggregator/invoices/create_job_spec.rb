# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Invoices::CreateJob do
  subject(:create_job) { described_class }

  let(:invoice) { create(:invoice) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::Invoices::CreateService).to receive(:call).and_return(result)
  end

  it "calls the aggregator create invoice service" do
    described_class.perform_now(invoice:)

    expect(Integrations::Aggregator::Invoices::CreateService).to have_received(:call)
  end
end
