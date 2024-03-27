# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::PostProcessJob, type: :job do
  let(:process_service) { instance_double(Events::PostProcessService) }
  let(:result) { BaseService::Result.new }

  let(:event) do
    create(:event)
  end

  it "calls the event post process service" do
    allow(Events::PostProcessService).to receive(:new)
      .with(event:)
      .and_return(process_service)
    allow(process_service).to receive(:call)
      .and_return(result)

    described_class.perform_now(event:)

    expect(Events::PostProcessService).to have_received(:new)
    expect(process_service).to have_received(:call)
  end
end
