# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillAddOnJob do
  let(:applied_add_on) { create(:applied_add_on) }
  let(:datetime) { Time.current.round }

  let(:invoice_service) { instance_double(Invoices::AddOnService) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Invoices::AddOnService).to receive(:new)
      .with(applied_add_on:, datetime:)
      .and_return(invoice_service)
    allow(invoice_service).to receive(:create)
      .and_return(result)
  end

  it "calls the add on create service" do
    described_class.perform_now(applied_add_on, datetime.to_i)

    expect(Invoices::AddOnService).to have_received(:new)
    expect(invoice_service).to have_received(:create)
  end

  context "when result is a failure" do
    let(:result) do
      BaseService::Result.new.single_validation_failure!(error_code: "error")
    end

    it "raises an error" do
      expect do
        described_class.perform_now(applied_add_on, datetime.to_i)
      end.to raise_error(BaseService::FailedResult)

      expect(Invoices::AddOnService).to have_received(:new)
      expect(invoice_service).to have_received(:create)
    end
  end
end
