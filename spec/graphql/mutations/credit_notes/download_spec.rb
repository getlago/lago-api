# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::CreditNotes::Download, type: :graphql do
  let(:required_permission) { 'credit_notes:view' }
  let(:credit_note) { create(:credit_note) }
  let(:organization) { credit_note.organization }
  let(:membership) { create(:membership, organization:) }

  let(:pdf_response) do
    File.read(Rails.root.join('spec/fixtures/blank.pdf'))
  end

  let(:mutation) do
    <<~GQL
      mutation($input: DownloadCreditNoteInput!) {
        downloadCreditNote(input: $input) {
          id
          fileUrl
        }
      }
    GQL
  end

  before do
    stub_request(:post, "#{ENV["LAGO_PDF_URL"]}/forms/chromium/convert/html")
      .to_return(body: pdf_response, status: 200)
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'credit_notes:view'

  it 'generates the credit note PDF' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: credit_note.id
        }
      },
    )

    result_data = result['data']['downloadCreditNote']

    aggregate_failures do
      expect(result_data['id']).to eq(credit_note.id)
      expect(result_data['fileUrl']).to be_present
    end
  end
end
