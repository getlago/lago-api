# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::GenerateFilesJob do
  let(:credit_note) { create(:credit_note) }
  let(:result) { BaseService::Result.new }
  let(:generate_pdf_service) { instance_double(CreditNotes::GenerateService) }
  let(:generate_xml_service) { instance_double(CreditNotes::GenerateXmlService) }

  it "delegates to the Generate service" do
    allow(CreditNotes::GenerateService).to receive(:new)
      .with(credit_note:, context: "api")
      .and_return(generate_pdf_service)
    allow(CreditNotes::GenerateXmlService).to receive(:new)
      .with(credit_note:, context: "api")
      .and_return(generate_xml_service)
    allow(generate_pdf_service).to receive(:call)
      .and_return(result)
    allow(generate_xml_service).to receive(:call)
      .and_return(result)

    described_class.perform_now(credit_note)

    expect(CreditNotes::GenerateService).to have_received(:new)
    expect(generate_pdf_service).to have_received(:call)
    expect(CreditNotes::GenerateXmlService).to have_received(:new)
    expect(generate_xml_service).to have_received(:call)
  end
end
