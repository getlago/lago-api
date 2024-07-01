require 'rails_helper'

RSpec.describe DataExports::ExportResourcesJob, type: :job do
  let(:data_export) { create(:data_export) }
  let(:result) { BaseService::Result.new }

  before do
    allow(DataExports::ExportResourcesService)
      .to receive(:call)
      .with(data_export:)
      .and_return(result)
  end

  it "calls ExportResources service" do
    described_class.perform_now(data_export)

    expect(DataExports::ExportResourcesService)
      .to have_received(:call)
      .with(data_export:)
  end
end
