require 'rails_helper'

RSpec.describe DataExports::CreateService, type: :service do
  subject(:result) do
    described_class.call(user:, format:, resource_type:, resource_query:)
  end

  let(:user) { create(:user) }

  let(:format) { "csv" }
  let(:resource_type) { "invoices" }
  let(:resource_query) do
    {
      "search_term" => "service 1",
      "filters" => {
        "currency" => "USD"
      }
    }
  end

  before do
    allow(DataExports::ExportResourcesJob).to receive(:perform_later)
  end

  it 'creates a new data export record' do
    aggregate_failures do
      expect(result).to be_success

      data_export = result.data_export
      expect(data_export.id).to be_present
      expect(data_export.user_id).to eq(user.id)
      expect(data_export.format).to eq("csv")
      expect(data_export.resource_type).to eq("invoices")
      expect(data_export.resource_query).to match(resource_query)
      expect(data_export.status).to eq("pending")
    end
  end

  it 'calls ExportResourcesJob' do
    data_export = result.data_export

    expect(DataExports::ExportResourcesJob)
      .to have_received(:perform_later)
      .with(data_export)
  end
end
