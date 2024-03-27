# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RefreshDraftJob, type: :job do
  let(:invoice) { create(:invoice) }
  let(:result) { BaseService::Result.new }

  let(:refresh_service) do
    instance_double(Invoices::RefreshDraftService)
  end

  it "delegates to the RefreshDraft service" do
    allow(Invoices::RefreshDraftService).to receive(:new).with(invoice:).and_return(refresh_service)
    allow(refresh_service).to receive(:call).and_return(result)

    described_class.perform_now(invoice)

    expect(Invoices::RefreshDraftService).to have_received(:new)
    expect(refresh_service).to have_received(:call)
  end
end
