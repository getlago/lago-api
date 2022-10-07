# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::GeneratePdfJob, type: :job do
  let(:credit_note) { create(:credit_note) }

  let(:generate_service) do
    instance_double(CreditNotes::GenerateService)
  end

  it 'delegates to the Generate service' do
    allow(CreditNotes::GenerateService).to receive(:new)
      .and_return(generate_service)
    allow(generate_service).to receive(:call_from_api)
      .with(credit_note: credit_note)

    described_class.perform_now(credit_note)

    expect(CreditNotes::GenerateService).to have_received(:new)
    expect(generate_service).to have_received(:call_from_api)
  end
end
